#ifndef _TCPCLIENT_H_
#define _TCPCLIENT_H_

// Most routines return 0 on success, -1 on failure.

#define TCPCLIENT_LOG_DBG  0
#define TCPCLIENT_LOG_INFO 1
#define TCPCLIENT_LOG_WARN 2
#define TCPCLIENT_LOG_ERR  3
#define TCPCLIENT_LOG_BUG  4

typedef int tcpclient_log_func_t(char *s);

int tcpclient_set_log_func(tcpclient_log_func_t *func, int new_log_lvl);

extern int tcpclient_set_prop_dbl(int con_h, char *name, double v);
// implemented properties:
//     timo_ms



extern int tcpclient_connect(char *ipaddr, int tcpport, int *con_h);
// desc: connects to server, returns a handle for future access.
// params: ipaddr = ip address of form xx.xx.xx.xx or other
//   tcpport = tcp port (if 0, it uses default)
//   con_h = set to new handle to server.  set to -1 on failure.
// returns: 0=succes, -1 = error

int tcpclient_send(int con_h, char *buf, int *n_bytes);
// desc: writes bytes to socket
// params: con_h = handle to socket
//         buf = bytes to write to the port
//         n_bytes = ptr to number of bytes to write.
//               set to num bytes written
// note: You can use this to write character zero to the port
// returns: 0 on success, non-zero on error

int tcpclient_recv(int con_h, char *buf, int *n_bytes);
// returns 0 on success


int tcpclient_disconnect(int con_h);
// desc: disconnects from server
// params: con_h = handle to connection to server
// returns: 0 on success, non-zero on error

int tcpclient_disconnect_all(void);


char *tcpclient_get_err_msg(void);

#endif

