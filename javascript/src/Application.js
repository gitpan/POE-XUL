// ------------------------------------------------------------------
// Portions of this code based on works copyright 2003-2004 Ran Eilam.
// Copyright 2007 Philip Gwyn.  All rights reserved.
// ------------------------------------------------------------------

var $application;
var groupbox_style = "border-color: #124578;";
var caption_style = "color: white; font-weight: bold; padding: 0px 9px 5px 9px; margin: 0px; -moz-border-radius: 3px; background-color: #124578; border: 1px solid #124578;";

function POEXUL_Application () {

    if( POEXUL_Application.singleton ) 
        return POEXUL_Application.singleton;

    this.applicationName = location.search.substr(1) || false;
    var matches = /app=(\w+)/.exec( this.applicationName );
    if( matches ) {
        this.applicationName = matches[1];
    }
    this.crashed = false;
    this.frames = [];
    this.other_windows = {};
    this.BLIP   = 10;

	this.runner = POEXUL_Runner.get();
    this.conduit = new POEXUL_Conduit ( this.baseURI() );
    $application = this;
    var b1 = new POEXUL_Status;
    this.init_window( window );
}

// ------------------------------------------------------------------
// Get the current application.  Create one if needs be
POEXUL_Application.get = function () {
    if( !POEXUL_Application.singleton ) 
        POEXUL_Application.singleton = new POEXUL_Application;
    return POEXUL_Application.singleton;
}

// ------------------------------------------------------------------
// Boot an instance of the application
POEXUL_Application.boot = function () {
    // Create the application
    POEXUL_Application.get();
    $application.runRequest();
}

// ------------------------------------------------------------------
// Connect the current window to an existing instance of the application
POEXUL_Application.connect = function ( sid ) {
    // Create the application
    POEXUL_Application.get();
    $application.setSID( sid );
    $application.runRequest( { event: 'connect' } );
}

// ------------------------------------------------------------------
// Get a reference to an <iframe>'s parent's Application singleton 
POEXUL_Application.fragment = function ( id ) {
    if( !POEXUL_Application.singleton ) {
        POEXUL_Application.singleton = 
            $application = window.parent.$application;
        $application.init_window( window );
        $application.init_fragment( document, window, id );
    }

    return POEXUL_Application.singleton;
}

var _ = POEXUL_Application.prototype;


// ------------------------------------------------------------------
// Add the event listeners to a window
_.init_window = function ( win ) {
    var self = this;
    win.addEventListener( 'command',
            function(event) { self.fireEvent_Command(event) }, false );
    win.addEventListener( 'change',
            function(event) { self.fireEvent_Change(event)  }, false );
    win.addEventListener( 'select',
            function(event) { self.fireEvent_Select(event)  }, false );
    win.addEventListener( 'pick',
            function(event) { self.fireEvent_Pick(event)  }, false );
    win.addEventListener( 'keypress',
            function(event) { self.fireEvent_Keypress(event)  }, true );
    win.addEventListener( 'unload',
            function(event) { self.unload(event)  }, true );
}

// ------------------------------------------------------------------
// Add the required CSS to the sub-window
_.init_fragment = function ( doc, win, id ) {
    if( doc.height < win.innerHeight ) {
//        alert( "doc.height=" + doc.height +
//                " < win.innerHeight=" + win.innerHeight );
        return;
    }

    var box = doc.getElementById( id );
    if( !box )
        this.crash( "Failed to find element " + id + " in the iframe." );
    box = box.parentNode;
    box.style.height = doc.height + "px";
    box.style.width  = doc.width + "px";
    if( doc.width > win.innerWidth ) {
        box.style.overflow = 'scroll';
    }
    else {
        box.style.overflow = '-moz-scrollbars-vertical';
    }

    return;
}


// ------------------------------------------------------------------
_.baseURI = function () {
    var pathname   = location.pathname.replace(/\/[^\/]+$/, "");
    var port       = location.port;
    port           = port? ':' + port: '';
    return uri = 'http://'+location.hostname + port + pathname + "/xul";
}

// ------------------------------------------------------------------
_.setSID = function ( SID ) {
    this.conduit.setSID( SID );
}

// ------------------------------------------------------------------
_.getSID = function ( ) {
    return this.conduit.getSID();
}

// ------------------------------------------------------------------
_.crash = function ( why ) {
    this.status( "error" );

    this.crashed = why;

    var data, already, xul, title, message, html;

    // Perl error
    var re = /((PERL|JAVASCRIPT|APPLICATION) ERROR)(\s*:?\s*)/m;
    var m = re.exec( why );
    if( m && m.length ) {
        title = m[1];
        message = why.substr( m[0].length );
        // Make it look nice
        message = message.replace( "&", "&amp;", "g" );
        message = message.replace( "<", "&lt;", "g" );
        message = message.replace( ">", "&gt;", "g" );
        message = message.replace( "\n", "<html:br />", "g" );
        xul = "<html:span style='font-family: monospace;'>" + message + "</html:span>";
    }        
    else if ( why.match( /^\s*<html>/ ) ) {
        // Keep HTML as-is
        html = why;
    }
    else {
        title = "Application crash";
        // Pretty-print any other text
        xul = why.replace( "\n", "<html:br/>", "g" );
        xul = "<html:p style='width:550px'>" + why + "</html:p>"
    }

    var mime;

    if( html ) {
        data = html;
        mime = "text/html";
    }
    else if( ! data ) {
        // this means it isn't HTML
        // So the alert won't look weird
        // alert( why );
        // already = 1;

        data = "<?xml version='1.0'?>\n" +
               "<?xml-stylesheet href='chrome://global/skin/' type='text/css'?>\n" +
               "<window xmlns='http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul' "+
                "xmlns:html='http://www.w3.org/1999/xhtml' " +
                "orient='vertical'>\n" +
               "<hbox><spacer flex='1'/><groupbox class='error' style='background-color: white; margin-top: 75px;" + groupbox_style + "'>" +
                    "<caption style='padding: 0;'><description style='" + caption_style + "'>"+ title + 
                    "</description></caption>" +
               "<hbox style='max-width:600px; min-width: 200px; overflow: auto;' flex='1'><vbox><image class='error-icon'/><spacer/></vbox>" +
                    "<description>" + xul + "</description></hbox>" +
                "</groupbox><spacer flex='1'/></hbox><spacer/></window>";
        mime = "application/vnd.mozilla.xul+xml";
    }
    try { 
        // btoa fails on unicode
        data = btoa( data );
    }
    catch( err ) {
        // If that's the case, show the alert (if not already ) and bug out
        if( ! already ) {
            alert( why );
        }
        throw( err );
    }
    window.location = "data:"+mime+";base64," + data;
}


_.isNotCrashed = function () {
    if( !this.crashed )
        return;
    alert( "This application has crashed\n" + this.crashed );
}


// ------------------------------------------------------------------
_.exception = function ( type, EXs ) {
    var msg = [];
    for( var q=0 ; q<EXs.length ; q++ ) {
        var ex = EXs[q];
        var file = ex.fileName || 'N/A';
        var line = ex.lineNumber || 'N/A';
        msg.push( (ex.message || ex.description) + 
                        "\n  File " + file + " line " + line );
    }

    $application.crash( type + " ERROR " + msg.join( "\n" ) );
}


// events ---------------------------------------------------------------------

_.fireEvent_Command = function (domEvent) {
	var source = domEvent.target;
	if (source.tagName == 'menuitem') {
		var realSource = source.parentNode;
		if (realSource.tagName == 'search-list') {
            // $debug( 'Select SearchList ' + realSource.selectedIndex );
			this.fireEvent( 'Select', 
                            { 'target': realSource },
                            { 'selectedIndex': realSource.selectedIndex }
                          );
            return;
		} 

		realSource = realSource.parentNode;
		if (realSource.tagName == 'menu') {
            // fb_log( "menu->Click" );
			this.fireEvent('Click', domEvent, {});
		} 
        else {
            // menulist: mozilla doesn't set selectedIndex properly!
            // Same with button, it seems
			var selectedIndex;
			if (realSource.tagName == 'button' || 
                    realSource.tagName == 'menulist' ) {
				var children = source.parentNode.childNodes;
				selectedIndex = children.length;
				while (selectedIndex--) if (children[selectedIndex] == source) break;
                // fb_log( realSource.tagName + "'s true index=" + selectedIndex );
                realSource.selectedIndex = selectedIndex;
			} else { 
				selectedIndex = realSource.selectedIndex;
			}
			this.fireEvent(
				'Select',
				{'target': realSource},
				{'selectedIndex': selectedIndex}
			);
		}
    } 
    else if (source.tagName == 'radio') {
       var realSource = source.parentNode;
       if (realSource.tagName == 'radiogroup') {
            this.fireEvent( 'RadioClick',
                                {'target': realSource},
                                {'selectedId':  source.getAttribute( 'id' ) }
                          );
        }
        else {
            //alert( "Why a click from "+ realSource.tagName + "." +
            //                            realSource.getAttribute( 'id' ) );
        }
    }
    else {

        if( FormatedField ) {
            var bp = domEvent.target.getAttribute( 'bypass' );
            if( !bp && !FormatedField.form_validate() ) {
                return;
            }
        }

        // fb_log( "Command->Click " + domEvent.type );
        this.fireEvent('Click', domEvent, {});
	}
}

_.fireEvent_Select = function (domEvent) {
	var source = domEvent.target;
	var selectedIndex = source.selectedIndex;
	if (selectedIndex == -1) return; // listbox: mozilla fires strange events
    // textbox: mozilla fires this event when user selects text
    if (selectedIndex == undefined) return;
	this.fireEvent
		('Select', {'target': source}, {'selectedIndex': selectedIndex });
}

_.fireEvent_Pick = function (domEvent) {
	var source = window.document.getElementById(domEvent.targetId);
	this.fireEvent('Pick', {'target': source}, {'color': source.color });
}

_.fireEvent_Change = function (domEvent) { 

    var target = domEvent.target;
    this.fireEvent('Change', domEvent, {'value': target.value}) 
}

_.fireEvent_Keypress = function (e) { 

    if( e.altKey || e.ctlKey || e.shiftKey || e.metaKey || e.isChar )
        return;
    var f = e.keyCode - 111;
    if( f < 1 || 12 < f )
        return;
    var name = "F" + f;

    e.stopPropagation();
    if( e.cancelable )
        e.preventDefault();

    var buttons = document.getElementsByTagName( 'button' );
    // fb_log( "Pressed "+name );
    for( var q = 0 ; q < buttons.length ; q++ ) {
        var B = buttons[q];
        if( Element.isVisible( B ) ) {
            var fkey = B.getAttribute( 'fkey' );
            if( fkey && fkey.toUpperCase() == name ) {
                // fb_log( "Clicking " + B.label );
                B.focus();
                B.click();
                return;
            }
        }
    }
}

// private --------------------------------------------------------------------

_.fireEvent = function (name, domEvent, params) {
	var source   = domEvent.target;
	var sourceId = source.id;
	if (!sourceId) return; // event could come from some unknown place
	var event = {
		'source_id' : sourceId,
		'event'   : name,
	};
    if( 0 ) {  // XUL doesn't believe in checked, it seems
        event['checked'] = source.getAttribute('checked');
    }
    else {
        event['checked'] = source.getAttribute('selected');
    }

	var key; for (key in params) event[key] = params[key];
	this.runRequest(event);
}


// ------------------------------------------------------------------
// turn an event into something we should send to the server
_.setupEvent = function ( event ) {
    if( !event ) {
        event = {};
    }
    event.app = this.applicationName;
    if( ! ("window" in event) )
        event.window = window.name;
    return event;
}


// ------------------------------------------------------------------
// event should be :
//  {
//      event: "Click",
//      source_id: id,
//    For 'Change':
//      value: "new value",
//    For 'RadioClick':
//      selectedId: itemId
//      checked: source.selected
//    For 'Select':
//      selectedIndex:
//      checked: source.selected
//    Conduit will add :
//      SID: current-SID,
//      reqN: 1++,
//    Added in setupEvent :
//      app: "IGDAIP", (or the application name)
//      window: popup-window-name
//  }

_.runRequest = function (event) {
    this.isNotCrashed();

    event = this.setupEvent( event );

    var self = this;
    this.status( "load" );
    this.conduit.request( event, 
                          function (json) { self.runResponse( json ) } 
                        );
}


// ------------------------------------------------------------------
_.runResponse = function ( json ) {

    this.status( "run" );

    if( json == null ) {
        this.crash( "Response didn't include JSON" );
    }
    else if( 'object' != typeof json && 'Array' != typeof json ) {
        this.crash( "Response isn't an array: " + typeof json );
    }
    else {
        this.runner.run( json );
    	this.status( "done" );
    }
    return;
}

// ------------------------------------------------------------------
_.status = function ( status ) {

    var text;
    if( status == 'load' ) {
        // document.documentElement.style.cursor = "wait";
        text = "Chargement...";
    }
    else if( status == 'run' ) {
        text = "Ex\xe9cution...";
    }
    else if( status == 'done' ) {
        document.documentElement.style.cursor = "auto";
        text = "Pr\xEAt";
    }
    else if( status == 'error' ) {
        document.documentElement.style.cursor = "auto";
        text = "Erreur";
    }
    else {
        test = "En cour : " + text ;
    }

    var message = window.document.getElementById( 'XUL-Status' );
    if( message ) {
        var textNode = window.document.createTextNode( text );
        message.replaceChild( textNode, message.childNodes[0] );
        window.status = ' ';
    }
    else {
        window.status = text;
    }
}

// ------------------------------------------------------------------
_.clearFormated = function () {
    if( FormatedField ) {
        FormatedField.clear_formated();
    }
}

_.cleanFormated = function () {
    if( FormatedField ) {
        FormatedField.clean_formated();
    }
}


// ------------------------------------------------------------------
_.timing = function ( what, start, end ) {
    var elapsed = end - start;
    var t;
    if( elapsed > 1000 ) {
        t = ( elapsed/1000 ) + "s";
    }
    else {
        t = elapsed + "ms";
    }
    // window.status = window.status + " " + what + ": " + t;
    // $debug( what + ": " + t + "\n" );
}

// ------------------------------------------------------------------
// Open a sub-window
_.openWindow = function ( url, id, features ) {
    var w = window.open( url, id, features );

    this.other_windows[ id ] = window.open( url, id, features );
    
    var self = this;

    w.addEventListener( 'unload', 
                        function (e) { self.closed( id, e ); return true; }, 
                        false 
                      );
}

// ------------------------------------------------------------------
// Close a sub-window
_.closeWindow = function ( id ) {
    fb_log( id + ".close()" );
    var w = this.other_windows[ id ];

    if( !w ) {
        // either window was already closed, or we are the popup
        if( window.name == id ) {
            w = window;
        }
    }

    if( window.name == w.name ) {
        fb_log( "Closing ourself" );
        if( w.opener && w.opener['$application'] ) {
            fb_log( "Getting main window to close us" );
            w.opener['$application'].closeWindow( id );
            return;
        }
    }

    if( w && !w.closed )
        w.close();      // this should provoke .closed()
                        // which handles the 'disconnect'
}

// ------------------------------------------------------------------
// Main window is closing, close sub-windows
_.unload = function ( e ) {
    this.unloading = 1;
    for ( var id in this.other_windows ) {
        fb_log( id + '.close()' );
        this.other_windows[ id ].close();
    }
}

// ------------------------------------------------------------------
// Sub window is closing
_.closed = function ( id, e ) {
    if( this.unloading )        // skip out early
        return;
    if( ! e.target.location ) 
        return;
    if( e.target.location.toString() == 'about:blank' )   
        return;                 // this is unloading the initial about:blank
//    fb_log( e.target.location.toString() );
    fb_log( "Window " + id + " closed" );
    if( this.other_windows[ id ] ) {
        delete this.other_windows[ id ];
        var self = this;
        window.setTimeout( function () { self.disconnect( id ); }, this.BLIP );
    }
}


// ------------------------------------------------------------------
// Disconnect a sub window is closing
_.disconnect = function ( id ) {
    this.runRequest( { event: 'disconnect', 
                       window: id 
                   } );
}

// ------------------------------------------------------------------
// Instructions for another window
_.for_window = function ( accume ) {
    for( var id in accume ) {
        var w = this.other_windows[ id ];

        var name = id;
        if( !w && window.name == id ) {
            // either window was already closed, or we are the main window
            w = window;
            name = 'main window';
        }
        var cmds = accume[ id ];
        delete accume[ id ];
        fb_log( "Instructions for |" + name + "| + count=" + cmds.length );
        w['$application'].runResponse( cmds );
    }
}
