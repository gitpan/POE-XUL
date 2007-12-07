// ------------------------------------------------------------------
// Copyright 2007 Philip Gwyn.  All rights reserved.
// ------------------------------------------------------------------

// ------------------------------------------------------------------
// Create the Class.inherit() method
Object.extend( Function.prototype, {
    inherit: function( obj ) {
        Object.extend( this.prototype, obj.prototype );
    }
});

// ------------------------------------------------------------------
// Create some useful methods in String
String.prototype.substring2 = function ( pos0, pos1, newS ) {
    return this.substring( 0, pos0 ) + newS + this.substring( pos1 );
}
String.prototype.substr2 = function ( pos0, len, newS ) {
    return this.substring( 0, pos0 ) + newS + this.substring( pos0+len );
}

String.prototype.reverse = function () {
    var ret = '';
    for( q = this.length-1 ; q>-1 ; q-- )
       ret += this.charAt(q);
    return ret;
}

// ------------------------------------------------------------------
String.prototype.html_escape = function () {
    function html_match (match) {
        return '&#' + match.charCodeAt( 0 ) + ';';
    }
    var text = this;
    return text.replace( /[\x80-\xff]/mg, html_match );
}



// ------------------------------------------------------------------
function focus_next_input( field ) {
    if( ! field.form ) {
        field.blur();
        return;
    }
    var i;
    // Find the current field's offset
    for (i = 0; i < field.form.elements.length; i++) {
        if (field == field.form.elements[ i ])
            break;
    }
    // Move focus to next field
    i = (i + 1) % field.form.elements.length;
    field.form.elements[ i ].focus();
    // field.blur();
}

// ------------------------------------------------------------------
function rollup(id, textOFF, textON) {
    var down    = $( "DOWN_" + id);
    var up      = $( "UP_" + id);
    var widget  = $( "WIDGET_" + id );
    
    if( !down )
        alert( "Missing DOWN_" + id );
    if( !widget )
        alert( "Missing WIDGET_" + id );

    if( !down || !widget ) {
        return false;
    }
    if( Element.visible( down ) ) {
        rollup_set( widget, textOFF, up, down );
    }
    else {
        rollup_set( widget, textON, down, up );
    }
    if( rollup.accordion ) {
        rollup_accordion( id, textOFF, textON ) ;
    }

    return false;
}
rollup.accordion = 1;

// ------------------------------------------------------------------
function rollup_set( widget, text, shown, hidden ) {

    if( shown )
        Element.show( shown );
    if( hidden )
        Element.hide( hidden );

    if( widget.textContent ) {
        widget.textContent = text;
    }
    else {
        widget.value = text;
    }
}

// ------------------------------------------------------------------
function rollup_accordion( down_id, textOFF, textON ) {
    
    var droppers = document.getElementsByTagName( 'groupbox' );
    fb_log( "Accordion on " + droppers.length + " elements" );
    for( var q = 0 ; q < droppers.length ; q++ ) {
        var gb = droppers[q];
        if( gb && gb.id && gb.id != down_id && 
                  gb.className && gb.className.match(/drop-down/) ) {
            
            var down    = $( "DOWN_" + gb.id );
            if( down && Element.visible( down ) ) {
                var widget = $( "WIDGET_" + gb.id );
                fb_log( "Drop down " + gb.id + " is down" );
                if( widget ) {
                    rollup_set( widget, textOFF, null, down );

                    fb_log( widget.id + ".onclick=" + 
                            widget.attributes['onclick'] );
                }
            }
        }
    }
}

// ------------------------------------------------------------------
function popup ( id, e ) {
    var el = $( id );
    if( el ) {
        if( Element.visible( el ) ) 
            Element.hide( el );
        else 
            Element.show( el );
    }

    if( e ) {
        e.stopPropagation();
        e.preventDefault();
    }
    return false;
}

// ------------------------------------------------------------------
function to_page( name ) {

    if( window.location.toString().match( /\.xul$/ ) ) {
        window.location = name + ".xul";
    }
    else {
        window.location = name + ".html";
    }
    return false;
}

// ------------------------------------------------------------------
function corner_div( side, width, background ) {
    var line = document.createElement( "div" );
    Element.setStyle( line, {
            height: "1px",
            overflow: "hidden",
            background: background,
        } );
    var m = "margin-"+side;
    line.style[ m.camelize() ] = width+"px";
    return line;
}

function corners ( id ) {
    var el = $( id );
    var dim = Element.getDimensions( el );
    var pos = Position.positionedOffset( el );
    
    // Left-side corner
    var left = document.createElement( "div" );
    var size = dim.height + "px";
    Element.setStyle( left, {
            width: size,
            height: size,
            overflow: "hidden",
            "background-color": "transparent",
            position: "fixed",
            top: pos[1] + "px",
            left: (pos[0] - dim.height) + "px"
        } );

    // Right-side corner
    var right = document.createElement( "div" );
    Element.setStyle( right, {
            width: size,
            height: size,
            overflow: "hidden",
            backgroundColor: "transparent",
            position: "fixed",
            top: pos[1] + "px",
            left: pos[0] + dim.width + "px"
        } );
    
    document.body.appendChild( left );
    document.body.appendChild( right );

    var background = Element.getStyle( el, 'background-color' );
    
    for( var q=0; q< dim.height; q++ ) {        // >
        left.appendChild( corner_div( "left", Math.round(q/2), background ) );
        right.appendChild( corner_div( "right", Math.round(q/2), background ) );
    }
}

// ------------------------------------------------------------------
function flush_right ( id ) {
    var el = $( id );
    var dim = Element.getDimensions( el );
    var pos = Position.positionedOffset( el );

    var body_dim = Element.getDimensions( document.body );

    // width of body - width of div - width of slope to the right - fudge
    el.style.left = (body_dim.width - dim.width - dim.height/2 -5 ) + "px";
    return;
}

// ------------------------------------------------------------------
function isalpha ( c ) {
    c = c.substr( 0, 1 );
    return ( c.toLowerCase() != c.toUpperCase() ? true : false );
}

// ------------------------------------------------------------------
// Set the size of some of the XUL elements based on window size
function set_window_style() {

}


// ------------------------------------------------------------------
// show a message in the firebug console, if it exists
function fb_log( text ) {
    if( window['console'] && window['console']['log'] ) {
        console.log( text );
    }
}

// ------------------------------------------------------------------
function $debug ( string ) {
    if( window['console'] && window['console']['log'] ) {
        console.log( string );
    }
}


// ------------------------------------------------------------------
// Create some useful methods in Element
// Lifted from prototype's unittest.js
Element.isVisible = function(element) {
    element = $(element);
    if(!element) return false;
    if(!element.parentNode) return true;
    if(element.style && Element.getStyle(element, 'display') == 'none')
        return false;
    
    return Element.isVisible( element.parentNode );
}

