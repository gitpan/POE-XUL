// ------------------------------------------------------------------
// Portions of this code based on works copyright 2003-2004 Ran Eilam.
// Copyright 2007 Philip Gwyn.  All rights reserved.
// ------------------------------------------------------------------
function Throw(a, b) {
        var message       = b? (a.message || a.description) + "\n" + b: a;
        var exception     = b? a: new Error;
        exception.message = exception.description = message;
        throw exception;
}


function POEXUL_Runner () {

    if( POEXUL_Runner.singleton ) 
        return POEXUL_Runner.singleton;

    this.document = window.document;

    this.BLIP = 5;
    this.slice_size = 53;
    this.timeouts = {};
}

var _ = POEXUL_Runner.prototype;

POEXUL_Runner.get = function () {
    if( !POEXUL_Runner.singleton ) 
        POEXUL_Runner.singleton = new POEXUL_Runner;
    return POEXUL_Runner.singleton;
}
 
// ------------------------------------------------------------------
_.run = function ( response ) {

    this.start = Date.now();
	this.resetBuffers();

    var commands = [];
	for( var R=0; R < response.length; R++ ) {
        commands.push( {
                methodName: response[R][0],
                nodeId: response[R][1],
                arg1: response[R][2], 
                arg2: response[R][3],
                arg3: response[R][4],
                arg4: response[R][5],
            } );
    }

    this.EXs = [];
    this.nCmds = commands.length;

    if( commands.nCmds > this.slice_size && $status ) {
        fb_log( "running " + this.nCmds + " commands" );
        $status.progress( 0, this.nCmds );
        $status.show;
    }

    this.runCommands( commands );
}

// ------------------------------------------------------------------
// Run the commands
_.runCommands = function ( commands ) {
    if( commands.length )
        this.runBatch( commands, 0 );
    if( ! commands.length ) 
        this.runFinished();
}

// ------------------------------------------------------------------
// Run a batch of commands, then give up a time-slice
_.runBatch = function ( commands, late ) {

    if( late )
        fb_log( 'runBatch n=' + commands.length + " late=" + late );
    var count = 0;
    while( commands.length ) {
        count++;
        try {
            
            var cmd = commands.shift();
            if( late && 0 ) 
                fb_log( 'runBatch count=' + count + 
                            " command=" + cmd.nodeId + "." + cmd.arg1 );
            this.late = late;
            var rv = this.runCommand( cmd );
            this.late = 0;

            if( rv || count > this.slice_size ) {
                if( $status ) 
                    $status.progress( (this.nCmds - commands.length), 
                                       this.nCmds );
                this.deferCommands( commands, late );
                return;
            }
        }
        catch ( ex ) {
            fb_log( 'exception = ' + ex );
            this.EXs.push( ex );
        }
    }
}

// ------------------------------------------------------------------
// Commands are done
_.runFinished = function () {

    // fb_log( 'runFinished' );
    if( $status ) {
        $status.progress( this.nCmds, this.nCmds );
    }

    this.addNewNodes();
    this.runLateCommands( 1 );
}

// ------------------------------------------------------------------
// Give up a "timeslice" so the UI can be updated
// This is important for XBL anonymous content
_.deferCommands = function ( commands, late ) {
    var self = this;
    var blip = self.BLIP;
    if( late ) 
        blip *= 20;
    if( late ) 
        fb_log( 'defer n=' + commands.length + 
                        " late=" + late + 
                        " blip=" + blip );
    window.setTimeout( function () { 
                                if( late == 0 ) {
                                    self.runCommands( commands );
                                }
                                else {
                                    self._runLateCommands( commands, late );
                                }
                            }, 
                            blip
                         );
}


// ------------------------------------------------------------------
_.addNewNodes = function () {

    var roots = this.newNodeRoots
	for( var parentId in roots ) {
        // prototype.js's Object.each is getting into our Array
        if( 'object' == typeof roots[parentId] ) {
            for( var child in roots[parentId] ) {
                // prototype.js's Object.each is getting into our Array
                if( 'object' == typeof roots[parentId][child] ) {
                    //alert( "parentID="+parentId+ " child=" +
                    //                        roots[parentId][child] );
                    this.addElementAtIndex( this.getNode(parentId),
                                            roots[parentId][child]
                                          );
                }
            }
        }
    }
    this.newNodeRoots = [];
}

// ------------------------------------------------------------------
_.runLateCommands = function ( age ) {

    fb_log( 'runLateCommands' );
    if( $status )
        $status.hide();

    if( age > 10 ) {
        alert( "Too many loops! age=" + age );
    }
    else {
        var lateCommands = this.lateCommands;
        if( lateCommands.length ) {
            this.lateCommands = [];
            this.deferCommands( lateCommands, age );
            return;
        }
    }
    this.runDone();
}

// ------------------------------------------------------------------
_._runLateCommands = function ( lateCommands, age ) {
    fb_log( 'late commands age=' + age + " n=" + lateCommands.length );

    this.runBatch( lateCommands, age );

    if( lateCommands.length )       // defered to later
        return;

    this.runDone();
}

// ------------------------------------------------------------------
_.runDone = function () {
    // we are really finished
    if( $status )
        $status.hide();
    this.slice_size = 971;
    this.resetBuffers();
    this.handleExceptions();

    this.nCmds = 0;
    this.booting = false;
}

// ------------------------------------------------------------------
_.handleExceptions = function () {
    if( this.EXs.length ) {
        var ex = this.EXs;
        this.EXs = [];
        this.largeThrow( ex );
    }
}

_.largeThrow = function ( EXs ) {

    $application.exception( "JAVASCRIPT", EXs );
}

// commands -------------------------------------------------------------------

// Run one command.
// Returning 1 means we want to give up a timeslice
_.runCommand = function (command) {
	var methodName = command['methodName'];
	var nodeId     = command['nodeId'];
	var arg1       = command['arg1'];
	var arg2       = command['arg2'];
	var arg3       = command['arg3'];
    rv             = 0;
	if (methodName == 'new') {
		if (arg1 == 'window')
			this.commandNewWindow(nodeId);
        else
			this.commandNewElement(nodeId, arg1, arg2, arg3);
    }
    else if (methodName == 'textnode' ) {
        this.commandNewTextNode( nodeId, arg1, arg2 );
    }
	else if (methodName == 'SID') {
        $application.setSID( nodeId );
    }
	else if (methodName == 'boot') {
        if( $status )
            $status.title( nodeId );
        this.booting = true;
        rv = 1;
    }
	else if ( methodName == 'bye' ) {
	    this.commandByeElement(nodeId);
    }
	else if ( methodName == 'bye-textnode' ) {
	    this.commandByeTextNode( nodeId , arg1 );
    }
    else if( methodName == 'set' ) {
        if ( !this.late && ( POEXUL_Runner.lateAttributes[arg1] || 
                        this.isLateCommand( command ) ) ) {
            // fb_log( 'late = ' + nodeId + "." + arg1 + "=" + arg2 );
            this.lateCommands.push(command);
        }
        else {
            rv = this.commandSetNode(nodeId, arg1, arg2);
        }
    }
    else if( methodName == 'remove' ) {
        this.commandRemoveAttribute(nodeId, arg1);
    }
    else if( methodName == 'javascript' ) {
        this.commandJavascript( arg1 );
    }
    else if( methodName == 'ERROR' ) {
        $application.crash( arg1 );
    }
    else if( methodName == 'cdata' ) {
        this.commandCDATA( nodeId, arg1, arg2 );
    }
    else if( methodName == 'framify' ) {
        if( this.late == 2 ) {               // framify is extra late
            this.commandFramify( nodeId );
        }
        else {
            this.lateCommands.push( command );
        }
    }
    else if( methodName == 'popup_window' ) {
        this.commandPopupWindow( nodeId, arg1 );
    }
    else if( methodName == 'close_window' ) {
        this.commandCloseWindow( nodeId );
    }
    else if( methodName == 'timeslice' ) {
        fb_log( methodName );
        rv = 2;
    }
    else {
        alert( "Unknown command " + methodName );
    }
    return rv;
}

// ------------------------------------------------------------------
_.isLateCommand = function ( command ) {
    var nodeId     = command['nodeId'];
    var key        = command['arg1'];
    var element = this.newNodes[nodeId];
    if (!element) element = this.getNode(nodeId, 1);
    if (!element) return true;
    if( key == 'textNode' && element.nodeName == 'script' ) {
        return true;
    }
    if( key == 'value' && element.nodeName == 'search-list' ) {
        // console.log( 'late value=' + command['arg2'] );
        return true;
    }
    return false;
}

// ------------------------------------------------------------------
_.commandNewWindow = function (nodeId) {
	this.windowId = nodeId;
}

// ------------------------------------------------------------------
_.commandNewElement = function (nodeId, tagName, parentId, index) { 
    try {
        var element = this.createElement(tagName, nodeId);
        element.setAttribute('_addAtIndex', index);
        this.newNodes[nodeId] = element;

        var parent = this.newNodes[parentId];
        if (parent)
            this.addElementAtIndex(parent, element);
        else {
            // New elements are added to existing nodes in one batch
            // in addNewNodes
            if( ! this.newNodeRoots[parentId] )
                this.newNodeRoots[parentId] = [];
            this.newNodeRoots[parentId].push( element );
        }

        if (tagName == 'listbox') {
            // onselect works but addEventListener( 'select' ) doesn't
            element.setAttribute( 'onselect', 
                                    '$application.fireEvent_Select(event);' );
            //element.addEventListener( 'select', 
            //         function (e) { alert( 'select' ); 
            //                $application.fireEvent_Select( e ) }, true );
        }
        else if (tagName == 'colorpicker') {
            element.setAttribute(
                'onselect',
                '$application.fireEvent_Pick({"targetId":"' +
                    element.id + '"})'
            );
        }
    } catch (e) {
        Throw(e,
            'Cannot create new node : [' + nodeId +
            ', ' + tagName + ', ' + parentId + ']'
        );
    }
}

// ------------------------------------------------------------------
_.commandCDATA = function ( nodeId, index, data ) { 
    try {
        var cdata = this.document.createCDATASection( data );

        var element = this.newNodes[nodeId];
        if (!element) element = this.getNode(nodeId);

        if ( index < element.childNodes.length ) {
            element.replaceChild( cdata, element.childNodes[index] );
        }
        else {
            element.appendChild( cdata );
        }

        if( element.nodeName == 'script' &&
                element.getAttribute( 'type' ) == 'text/javascript' ) {
            this.lateCommands.push( { methodName: 'javascript', 
                                      nodeId: nodeId, 
                                      arg1: data 
                                  } );
        }
    } catch (e) {
        Throw(e,
                'Cannot create new CDATA: ' + nodeId +
                        '[' + index + ']=' + data 
            );
    }
}

// ------------------------------------------------------------------
_.commandNewTextNode = function ( nodeId, index, text ) { 
    try {
        var tn = this.document.createTextNode( text );

        var element = this.newNodes[nodeId];
        if( !element ) 
            element = this.getNode(nodeId);
        if( index < element.childNodes.length ) {
            var el = element.replaceChild( tn, element.childNodes[index] );
            // work around the fact XBL doesn't call destuctor
            if( el.dispose )
                el.dispose();
        }
        else {
            element.appendChild( tn );
        }
    } catch (e) {
        Throw(e,
                'Cannot create new TextNode: ' + nodeId +
                        '[' + index + ']=' + text 
            );
    }
}

// ------------------------------------------------------------------
_.commandByeTextNode = function ( nodeId, index ) { 
    try {
        var element = this.newNodes[nodeId];
        if (!element) 
            element = this.getNode(nodeId, 1);
        if (!element)
            return;
        if ( index < element.childNodes.length ) {
            element.removeChild( element.childNodes[index] );
        }
    } catch (e) {
        Throw(e,
                'Cannot remove TextNode: ' + nodeId + '[' + index + ']'
             );
    }
}

// ------------------------------------------------------------------
_.commandSetNode = function (nodeId, key, value) { 
    var rv = 0;
    try {
        if( this.changedIDs[ nodeId ] ) {
            nodeId = this.changedIDs[ nodeId ];
        }

        var freshNode = true;
        var element = this.newNodes[nodeId];
        if (!element) {
            freshNode = false;
            element = this.getNode(nodeId, 1);
        }

        if( !element ) {
            if( !this.late ) 
                alert( "Missing new element" + nodeId );
            return;
        }

        if (key == 'textNode') {
            element.appendChild(this.document.createTextNode(value));
            return;
        }

        if (POEXUL_Runner.boleanAttributes[key]) {
            value = (value == 0 || value == '' || value == null)? false: true;
            if (!value) {
                element.removeAttribute(key);
            }
            else {
                element.setAttribute(key, 'true');
            }
            return;
        }

        if (POEXUL_Runner.simpleMethodAttributes[key]) {
            if (element.tagName == 'window')
                window[key].apply(window, [value]);
            else if( element[key] ) {
                // fb_log( element.id + "." + key + " (late="+this.late+")" );
                element[key].apply(element, [value]);
            }
            else {
                // still too early to run this
                this.lateCommands.push( { methodName: 'set',
                                          nodeId: element.id,
                                          arg1: key,
                                          arg2: value
                                      } );
            }
            return;
        }
        if( key == 'id' ) {
            if( this.newNodes[ nodeId ] ) {
                this.newNodes[ value ] = this.newNodes[ nodeId ];
                delete this.newNodes[ nodeId ];
                this.changedIDs[ nodeId ] = value;
            }
        }

        if( key == 'scrollTop' || 
                    ( key == 'style' && 
                        ( value.match( 'display:' ) || value == '' ) ) ||
                    ( key == 'value' ) ) {
            // if( !this.booting ) 
            //    fb_log( element.id + "." + key + "=" + value );            
        }

        if ( POEXUL_Runner.propertyAttributes[key] ) {
            this.commandSetProperty( element, key, value );
        }
        else if( !freshNode && POEXUL_Runner.freshAttributes[ key ] ) {
            // fb_log( "non-fresh " + key + "=" + value );
            this.commandSetProperty( element, key, value );
            element.setAttribute( key, value );
        }
        else {
            element.setAttribute( key, value );
        }
    } 
    catch (e) {
        Throw(e,
            'Cannot do set on node: [' + nodeId + ', ' + key + ', ' + value + ']'
        );
    }
    return rv;
}

// ------------------------------------------------------------------
_.commandSetProperty = function ( element, key, value ) {
    if (key == 'selectedIndex') {
        return this.commandSelectedIndex( element, value );
    }
    if( 0 ) {
        var js = '$("'+element.id+'").' + key + '=' + value;
        fb_log( js );
        eval( js );
    }
    else {
        element[key] = value;
    }

}

// ------------------------------------------------------------------
_.commandSelectedIndex = function ( element, value, _try ) {

    element.setAttribute("suppressonselect", true);

    // fb_log( "property " + element.id + ".selectedIndex=" + value );
    var done;
    if( value >= 0 ) {
        var popup = element.menupopup;
        if( !popup ) {
            this.deferSelectedIndex( element, value, _try );
            return;
        }


        var sel = popup.childNodes[value];
        // fb_log( '.selectedItem = ' + sel );
        element.selectedIndex = value;
        // element.selectedItem = sel;
        fb_log( element.id + '.selectedItem.id = ' + element.selectedItem.id );
        // fb_log( element.id + '.selectedIndex = ' + element.selectedIndex );
        done = true;
    }
    if( ! done ) {
        element.selectedItem = null;
    }

    element.removeAttribute( "suppressonselect" );
    return;
}

// ------------------------------------------------------------------
_.deferSelectedIndex = function ( element, value, _try ) {

    if( !_try ) _try = 0;
    // fb_log( element.id + " has no menupopup try=" + _try );
    var tid = "SelectedIndex" + element.id;
    _try++;
    if( _try < 6 ) {
        // only the last one will stay in the loop
        if( this.timeouts[tid] ) 
            window.clearTimeout( this.timeouts[tid] );
        var self = this;
        this.timeouts[tid] = window.setTimeout( function () {
                        self.commandSelectedIndex( element, value, _try );
                        delete self.timeouts[tid];
                     }, 250 );
    }
    else {
        element.selectedIndex = value;
        fb_log( 'Giving up on ' + element.id );
    }
}
// ------------------------------------------------------------------
_.commandRemoveAttribute = function (nodeId, key, value) { 
    try {
        var element = this.newNodes[nodeId];

        if (!element) element = this.getNode(nodeId);
        element.removeAttribute( key );
    } catch (e) {
        Throw(e,
            'Cannot do remove attribute from node: [' + nodeId + ', ' + key + ']'
        );
    }
}

// ------------------------------------------------------------------
_.commandSetTextNode = function ( element, nodeId, value ) {

    if (element.nodeName == 'script') {
        this.commandJavascript( value );
        return;
    }

    var textNode = this.document.createTextNode(value);
    // Look for an existing textNode
    if ( element.hasChildNodes() ) {
        var children = element.childNodes;
        for( var q=0 ; q < children.length ; q++ )  {
            var child = children[ q ];
            // HTML nodes might need .tagName
            if( child.nodeName == '#text' ) {
                // And replace it
                element.replaceChild( textNode, child );
                return;
            }
        }
    }
    // None exist.  So append one
    element.appendChild( textNode );
    return;
}

// ------------------------------------------------------------------
_.commandJavascript = function ( value ) {
    try {
        eval( value );
    } catch( e ) {
        Throw(e, 'Cannot evaluate javascript: ['+ value + ']' );
    }
}

// ------------------------------------------------------------------
// Delete an element
_.commandByeElement = function (nodeId) {
    // fb_log( 'bye ' + nodeId );

    var node = this.newNodes[nodeId];
    if( node ) {
        delete this.newNodes[nodeId];
        // fb_log( 'bye new node' );
        // above is probably enough... but one can never be too paranoid
    }
    else {
        node = this.getNode( nodeId, 1 );
        if( !node ) {
            // fb_log( 'Attempt to remove unknown node ' + nodeId );
            return;
        }
    }

    // Remove from DOM
    var p = node.parentNode;
    if( p ) 
        p.removeChild( node );

    // work around the fact XBL doesn't always call destuctor
    if( node.dispose )
        node.dispose();
}

// ------------------------------------------------------------------
_.commandFramify = function (nodeId) {
    $application.framify( nodeId );
}

// ------------------------------------------------------------------
_.commandPopupWindow = function (id, win) {
    fb_log( "Open window "+id );
    var feat = "resizable=yes,dependent=yes";
    if( win.width ) {
        feat += ",width="+win.width;
    }
    if( win.height ) {
        feat += ",height="+win.height;
    }
    feat += ",location="+( win.location ? 'yes' : 'no' );
    feat += ",menubar="+( win.menubar ? 'yes' : 'no' );
    feat += ",toolbar="+( win.toolbar ? 'yes' : 'no' );
    feat += ",status="+( win.status ? 'yes' : 'no' );
    feat += ",scrollbars="+( win.status ? 'yes' : 'no' );

    if( ! win.url ) {
        var port       = location.port;
        port           = port ? ':' + port : '';
        win.url = 'http://' + location.hostname + port + 
            "/popup.xul?SID=" + $application.getSID() +
                    "&app=" + $application.applicationName;
    }

    $application.openWindow( win.url, id, feat );
}

// ------------------------------------------------------------------
_.commandCloseWindow = function (id) {
    fb_log( "Close window "+id );
    $application.closeWindow( id );
}

// private --------------------------------------------------------------------

_.getNode = function (nodeId, safe) {
	var node = this._getNode(nodeId);
	if ( !node && !safe ) Throw("Cannot find node by Id: " + nodeId);
	return node;
}

_._getNode = function (nodeId) {
    if( this.windowId == nodeId ) {
        return this.document.firstChild;
    }
    else {
        return this.document.getElementById(nodeId);
    }
}	

_.createElement = function (tagName, nodeId) {
	var element = tagName.match(/^html_/)?
		this.document.createElementNS(
			'http://www.w3.org/1999/xhtml',
			tagName.replace(/^html_/, '')
		):
		this.document.createElementNS(
			'http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul',
			tagName
		);
	element.id = nodeId;
	return element;
}

_.addElementAtIndex = function ( parent, child ) {

	var index = child.getAttribute('_addAtIndex');
	child.removeAttribute('_addAtIndex');
	
	if (index == null) {
		parent.appendChild(child);
		return;
	}
	var count    = parent.childNodes.length;
	if (count == 0 || index >= count ) {
		parent.appendChild( child );
    }
	else {
		parent.insertBefore( child, parent.childNodes[ index ] );
    }
}

_.resetBuffers = function () {
	this.newNodeRoots = []; // top level parent nodes of those not yet added
	this.newNodes     = []; // nodes not yet added to document
	this.lateCommands = []; // commands to run at latest possible time
    this.changedIDs   = {}; // old ID -> new ID
}

// These attributes should be true or non-existant
POEXUL_Runner.boleanAttributes = {
	'disabled'     : true,
	'multiline'    : true,
	'readonly'     : true,
	'checked'      : true,
	'selected'     : true,
	'hidden'       : true,
	'default'      : true,
	'grippyhidden' : true
};

// These attributes should be set as node properties ( node["key"] = value )
POEXUL_Runner.propertyAttributes = {
	'selectedIndex' : true,
    'scrollTop'     : true,
    'scrollBottom'  : true
};
// These attributes should be set as node properties after the node is
// part of the document (ie, after XBL activation), before that, as attributes
POEXUL_Runner.freshAttributes = {
	'value'         : true,
	'id'            : true,
};

// These attributes should be set after then node is added to the document
POEXUL_Runner.lateAttributes = {
	'selectedIndex' : true,
	'sizeToContent' : true,
	'focus'         : true,
	'blur'          : true,
    'scrollTop'     : true,
    'scrollBottom'  : true,
    'recalc'        : true
};
// These aren't in fact attributes, but methods
POEXUL_Runner.simpleMethodAttributes = {
	'sizeToContent'       : true,
	'ensureIndexIsVisible': true,
    'focus'               : true,
	'blur'                : true,
    'recalc'              : true
};

