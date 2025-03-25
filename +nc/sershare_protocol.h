// sershare.h
// type definitions for the Nucrypt protocol called "sershare",
// which allows a PC's serial ports to be used by a remote client.
// Typically used with NuCrypt boards
// Dan Reilly 6/10/2016


// All shorts are network order.
// All numbers are shorts (two bytes).

// Now in protocol version 2, when you specify a search key,
// it's no longer a string that matches but a list of chars,
// any of which terminate the read.

#ifndef _SERSHARE_PROTOCOL_H
#define _SERSHARE_PROTOCOL_H

// All sershare servers listen on this tcp port by default:
#define SERSHARE_TCPPORT 1492

#define SERSHARE_PROTOCOL_VERSION 2

// All sershare packets begin with this header,
// followed by a body of zero or more bytes.
typedef struct sershare_pkt_hdr_st {
  short pkttype; // one of SERSHARE_PKT_*
  short len;     // in network order (use htons). num bytes in the body
} sershare_pkt_hdr_t;

// requests
#define SERSHARE_PKTTYPE_CONREQ       0
#define SERSHARE_PKTTYPE_INQREQ       1
#define SERSHARE_PKTTYPE_OPENREQ      2
#define SERSHARE_PKTTYPE_SETPROPREQ   3
#define SERSHARE_PKTTYPE_CLOSEREQ     4
#define SERSHARE_PKTTYPE_READREQ      5
#define SERSHARE_PKTTYPE_SKIPREQ      6
#define SERSHARE_PKTTYPE_WRITEREQ     7
#define SERSHARE_PKTTYPE_MSWAITREQ    8
#define SERSHARE_PKTTYPE_EXITREQ      9
// responses
#define SERSHARE_PKTTYPE_OKRSP       10
#define SERSHARE_PKTTYPE_FAILRSP     11
#define SERSHARE_PKTTYPE_INQRSP      12
#define SERSHARE_PKTTYPE_OPENRSP     13
// read responses
#define SERSHARE_PKTTYPE_READTERMRSP 14
#define SERSHARE_PKTTYPE_READDONERSP 15
#define SERSHARE_PKTTYPE_READCONTRSP 16
#define SERSHARE_PKTTYPE_READTIMORSP 17

// Helper macro
#define SERSHARE_ISVALID_PKTTYPE(t) ((unsigned)(t)<=17)

/*
 The packet body (after the header) depends on the type.
   CONREQ: no body
     OKRSP: reponse is a short, indicating protocol version
   INQREQ: no body
     INQRSP: body is a concatenation of any number of null-terminated strings.
   OPENREQ is a string (not null term) that indicates the port name to open.
   OPENRSP: is a short, indicating port handle.
   CLOSEREQ: a short, indicating port handle to close.
      the response to CLOSERQ is OKRSP or FAILRSP.
   WRITEREQ: a short, indicating port handle to write to, followed by
      any number of characters (not null term).
   READREQ: a short, indicating port handle to read from, followed by
      a short (max num chars to read)
      server responds with a termrsp, timorsp, contrsp, or donersp
   SKIPREQ: Like a read, except it skips chars.
     The request packet body contains:
       port_h     (a short): port handle to read from
       max_len    (a long):  max num chars to skip, ~0=inf
       timo_ms    (a long): timeout in ms
       search_key (a null-terminated string): string to search for.  if
         omitted, previous search string is used
     The response to this is a termrsp, timorsp, or donersp.
       the body of the rsp is a long containing num bytes skipped.
   EXITREQ: no body. a graceful close.
   MSWAITREQ: is a long, indicating number of ms to delay.
      this causes server to do nothing for that many ms.
   SETPROPREQ: is a short (port handle) followed by two strings (both null term).
      the first string is a property name, and the second string is a property value.
      The following properties are currently implemented:
        property   value
          baud     string rep of dec num
          term     terminator search string

*/

//typedef struct sershare_readreq_pkt_st {
//  short pkttype;  // SERSHARE_PKTTYPE_RSP
//  short len;      // 2
//  short port_h;   // port handle
//  int   read_len; // max num chars to read
//} sershare_readreq_pkt_t;




// Maximum string length of search string
// or com port name
#define SERSHARE_MAX_NAME_LEN    32

// Maximum string length of terminator string
// or com port name
#define SERSHARE_MAX_PKT_LEN     512
#define SERSHARE_MAX_BODY_LEN    (SERSHARE_MAX_PKT_LEN-sizeof(sershare_pkt_hdr_t))


#endif
