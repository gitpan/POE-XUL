// ------------------------------------------------------------------
// Copyright 2007-2008 Philip Gwyn.  All rights reserved.
// ------------------------------------------------------------------

var $status;

function POEXUL_Status () {

    if( POEXUL_Status.singleton ) 
        return POEXUL_Status.singleton;

    this.msg = '';

    $status = this;
}

var _ = POEXUL_Status.prototype;


// ------------------------------------------------------------------
_.element = function () {
    var el = $( 'POEXUL-Status' );
    if( el && el.setTitle )
        return el;
    else 
        fb_log( "Can't find POEXUL-Status" );
    return;
}

// ------------------------------------------------------------------
_.title = function ( msg ) {
    var el = this.element();
    if( el ) {
        el.setTitle( msg );
        fb_log( "title=" + msg );
        window.document.firstChild.setAttribute( 'title', msg );
        this.show();
    }
    else {
        this.msg = msg;
        $application.status( msg );
    }
}

// ------------------------------------------------------------------
_.progress = function ( n, max ) {
    var el = this.element();
    if( el ) {
        el.setProgress( n, max );
        // fb_log( "progress=" + n + "/" + max );
        // this.show();
    }
    else {
        var perc = n/max*100;
        this.title( this.msg + " : " + perc.toPrecision(1) + "%" );
    }
}

// ------------------------------------------------------------------
_.show = function () {
    var el = this.element();
    // fb_log( 'status.show' );
    if( el ) {
        Element.show( el )
    }
    else {
        this.title( this.msg );
    }
}

// ------------------------------------------------------------------
_.hide = function () {
    var el = this.element();
    // fb_log( 'status.hide' );
    if( el ) {
        Element.hide( el )
    }
    else {
        this.title( '' );
    }
}

