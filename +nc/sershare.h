// client-side sershare API
// NuCrypt LLC
// Dan Reilly 7/20/2016

#ifndef _SERSHARE_H_
#define _SERSHARE_H_

// Most sershare routines return 0 on success, -1 on failure.

#define SERSHARE_LOG_DBG  0
#define SERSHARE_LOG_INFO 1
#define SERSHARE_LOG_WARN 2
#define SERSHARE_LOG_ERR  3
#define SERSHARE_LOG_BUG  4

typedef int sershare_log_func_t(char *s);
int sershare_set_log_func(sershare_log_func_t *func, int new_log_lvl);
// desc: tells sershare code the function it should use when logging,
//    so the text can go to the console, or a log file, or whatever.
//    It's best to do this before calling any other sershare routine.
//    You only need to do this once.
// params:
//    new_log_lvl = one of SERSHARE_LOG*
// returns: 0 always
// note: Use of this routine is entirely optional.

char *sershare_get_err_msg(void);
// desc: after any of the sershare routines return an error condition,
//    you can call this to get a better description of the problem.
// returns: string containing last error message

int sershare_connect(char *ipaddr, int tcpport, int *con_h);
// desc: connects to server, returns a handle for future access.
// params: ipaddr = ip address of form xx.xx.xx.xx or other form.
//   tcpport = tcp port (if 0, it uses default)
//   con_h = set to new handle to server.  set to -1 on failure.
// returns: 0=succes, -1 = error


int sershare_inq(int con_h, char *buf, int buf_len, int *rsp_len);
// desc: tells server to figure out which of its serial ports can
//   be opened.  The server responds with a list of concatenated
//   null-terminated strings.  This response is put into buf, and
//   possibly truncated.
// params: con_h = handle to connection to server
//         buf = filled in with list of ports (possibly truncated)
//         buf_len = length of buf.
//         rsp_len = if bigger than buf_len, means rsp was truncated
// returns: 0=succes, -1=err


int sershare_mswait(int con_h, int ms);
// desc: causes server to wait specified number of ms
// params: con_h = handle to connection to server
//         ms = number of ms
// returns: 0=succes, -1=err


int sershare_open(int con_h, char *serportname, int *port_h);
// desc: tells server to attempt to open named serial port on
//       that machine.
// params: con_h = handle to connection to server
//         serportname = name of serial port, such as "COM1"
//         port_h = handle to newly opened port
// returns: 0=succes, -1=err


int sershare_set_prop(int con_h, int port_h, char *prop_name, char *prop_val);
// desc: sets a property about a remote serial port
// params: con_h = handle to connection to server
//         port_h = hanldle to remote serial port
//         prop_name = name of property
//         prop_val = value of property
// returns: 0=succes, -1=err
//
//  The properties currently implemented by the server are:
//     prop_name    effect
//    baud        sets baud rate of serial port
//    terminator  sets sequence of chars that will terminate a read
//    timo        sets the read timeout (prop_val is dec num as string)



int sershare_write_n(int con_h, int port_h, char *buf, int len);
// desc: writes bytes to a remote serial port
// params: con_h = handle to connection to server
//         buf = bytes to write to the port
//         len = number of bytes to write
//         str = a null-terminated string to write to port
// note: You can use this to write character zero to the port
// returns: 0 on success, non-zero on error


int sershare_write(int con_h, int port_h, char *str);
// desc: writes a string to a remote serial port
// params: con_h = handle to connection to server
//         port_h = handle to remot port
//         str = a null-terminated string to write to port
// note: This does not write the zero character at the end of the string.
//       You can't use this routine to write character zero.
// returns: 0 on success, non-zero on error


int sershare_read(int con_h, int port_h, char *buf, int buf_len,
		  int timo_ms, char *search_key,
		  int *bytes_read, int *found_key, int *met_timo);
// desc: reads from a remote serial port
// params: con_h = handle to connection to server
//         port_h = handle to remot port
//         buf = filled with characters read from port
//         buf_len = maximum num of chars to read
//         timo_ms = timeout in ms (~0 means never timeout)
//         search_key = chars to search for. (null ptr means no search)
//         found_key = set to 1 if read ended because of terminator match
// returns: 0 on success, non-zero on error
// NOTE: bytes read is not restricted by the underlying protocol.
//       (that is, it can be bigger than SERSHARE_MAX_PKT_LEN).
// NOTE: This is now sershare protocol version 2, and the difference is that
//    the read will terminate at any of the chars in search_key, as opposed to
//    when there is a substring match.


int sershare_skip(int con_h, int port_h,
		  int max_len, int timo_ms, char *search_key,
		  int *bytes_read, int *found_key, int *met_timo);
// desc: causes server to read from a remote serial port and discard data
// params: con_h = handle to connection to server
//         port_h = handle to remote port
//         max_len = maximum num of chars to read (~0 means infinite)
//         timo_ms = timeout in ms (~0 means never timeout)
//         search_key = char string to search for. (null ptr means no search)
//         bytes_read = set to num bytes skipped
//         found_key = set to 1 if read ended because of terminator match
// returns: 0 on success, non-zero on error


int sershare_close(int con_h, int port_h);
// desc: closes a remote serial port
// params: con_h = handle to connection to server
//         port_h = handle to remote port
// returns: 0 on success, non-zero on error


int sershare_disconnect(int con_h);
// desc: server closes all the ports it had open, and
//       then we disconnect from that server.
// params: con_h = handle to connection to server
// returns: 0 on success, non-zero on error


int sershare_disconnect_all(void);
// desc: disconnects from all servers
// returns: 0=succes, -1=err

#endif
