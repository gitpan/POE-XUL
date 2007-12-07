// ------------------------------------------------------------------
// Portions of this code based on works copyright 2003-2004 Ran Eilam.
// Copyright 2007 Philip Gwyn.  All rights reserved.
// ------------------------------------------------------------------
function POEXUL_Conduit ( uri ) {

    this.queue = [];
    this.version = 1;
    this.SID = '';
    this.URI = uri || '/xul';
    this.requestCount = 0;
}

var _ = POEXUL_Conduit.prototype;

// ------------------------------------------------------------------
_.setSID = function ( SID ) {
    this.SID = SID;
}

// ------------------------------------------------------------------
_.getSID = function ( ) {
    return this.SID;
}

// ------------------------------------------------------------------
// Add the info we know about to the request to the request
_.setupRequest = function ( req ) {

    if( this.SID ) {
        req.SID = this.SID;
    }
    req.version = this.version;
    req.reqN = ++this.requestCount;
}

// ------------------------------------------------------------------
// Starts a new request
_.request = function ( req, callback ) {

    if( this.req ) {
        this.defer( req, callback );
        return;
    }

    this.setupRequest( req );

    window.status = '';
    this.time = Date.now();

    // $debug( "request=" + req.event );

    var self = this;
    window.status = this.URI;
    this.req = new Ajax.Request( this.URI, {
            parameters: req,
            onSuccess: function ( tr, json ) { self.onSuccess( tr, json, callback ) },
            onFailure: function ( tr, json ) { self.onFailure( tr, json ) },
            onException: function ( tr, e ) { self.onException( tr, e ) }
        } );
    this.req.event = req.event;
}

// ------------------------------------------------------------------
// Failed!
_.onFailure = function ( transport, json ) {

    var ct = transport.getResponseHeader( 'Content-Type' );
    if( ct == 'text/html' ) {
        $application.crash( transport.responseText );
    }
    else if( json && ! transport.responseText ) {
        $application.crash( "Failed: " + json );
    }
    else {
        $application.crash( "Failed: " + transport.responseText );
    }
}

// ------------------------------------------------------------------
// Browser failure!
_.onException = function ( transport, e ) {
    // $application.crash( "Exception: " + e.toString );
    throw( e );
}

// ------------------------------------------------------------------
// Success!
_.onSuccess = function ( transport, json, callback ) {
    
    // Allow other requests through
    // delete this['req'];

    if( !transport ) 
        return $application.crash( "Why no transport" );

    if( transport.status != 200 ) {
        return $application.crash( "Transport failure status=" + 
                                        transport.statusText + 
                                        " (" + transport.status + ")" );
    }

    if( !json )
        json = this.parseResponse( transport );

    if( json ) {
        callback( json );
        this.done();
    }
}

// ------------------------------------------------------------------
_.parseResponse = function ( transport ) {

    var ct = transport.getResponseHeader( 'Content-Type' );
    if( ct != 'application/json' ) {
        $application.crash( "We require json response, not " + ct );
        return;        
    }
    var text = transport.responseText;

    var size = transport.getResponseHeader( 'Content-Length' );
    if( 0 && text.length != parseInt( size ) ) {
        $application.crash( "XMLHttpRequest error: didn't receive the entire response got=" +
                            text.length.toString() + " vs expected=" +
                                size );
        return;
    }
    var json;
    try { 
        json = eval( "(" + transport.responseText + ")" );
    }
    catch (ex) {
        $application.exception( "JSON", [ ex ] );
    }
    return json;
}

// ------------------------------------------------------------------
// A request is finished.  
_.done = function () {
    $application.timing( 'Request', this.time, Date.now() );

    delete this['req'];
    this.do_next();
}

// ------------------------------------------------------------------
// Wait a bit for this request
_.defer = function ( req, callback ) {
    if( ! req.version ) 
        req.version = this.version;

    if( this.req.event == 'Click' ) {
        fb_log( "Attempted " + req.event + " during a " + this.req.event );
        alert( "Unable to send '" + req.event + "' at this time." );
        return;
    }

    this.queue.push( { 'req': req, 
                       'callback': callback
                   } );
}

// ------------------------------------------------------------------
// OK, now do it
_.do_next = function () {

    while( this.queue.length ) {
        var d = this.queue.shift();
        if( d.req.version >= this.version ) {  
            this.request( d.req, d.callback );
            return;    
        }
        alert( "version=" + d.req.version + " vs " + this.version );
        // Node versions changed.  Try the next one.
    }
}

// ------------------------------------------------------------------
// 
_.reqURI = function ( req ) {
    var params = new Hash( req );
    this.setupRequest( req );
    return this.URI + "?" + params.toQueryString();
}
