#ifndef _SER_H_
#define _SER_H_

#define SER_MAX_NAME_LEN 64

void ser_init(void);
// desc
//   typically call once before anything else
//   you may call ser_set_log_func before this,
//   so you can get log messages generated during the init

int ser_open(char *portname, int *port_h_p, int *baud_p);
// inputs
//   portname: file name of serial port to open
//   baud_p: requested baud
// outputs
//   port_h_p: on success, filled in withe the port index
//   baud_p: if port was already open, filled in with actual baud
//   returns 0 on success, non-zero on error

int ser_cfg_use_rts(int port_h, int en);

int ser_close(int port_h);
// inputs
//   port_h: indicates which port to close
// outputs
//   returns 0 on success, non-zero means err


int ser_write(int port_h, char *str);
// inputs
//   port_h: indicates which port to close
//   str: zero-terminated string to write to serial port
// outputs
//   returns 0 on success, non-zero means err

int ser_read(int port_h,
	     char *buf, int max_chars, int timo_ms, char *search_key,
	     int *chars_read, int *found_key, int *met_timo);
// inputs
//   port_h: which port to read from
//   buf: when reading, a pointer place to put the chars that are read.
//        if buf=0, this routine will skip chars but doesn't return any
//   max_chars: max number chars to read or skip.
//   search_key: a short string to search for.  If it's an empty string
//        IE "", it won't search, and will read as many chars as possible.
//   timo_ms: timeout in milliseconds. must be 0 or positive.
// outputs
//   buf: if non-zero, this buffer gets filled in
//   chars_read: equal to number of chars read or skipped (including search key)
//   met_timo: 0=did not meet timeout, 1=met timeout
//   found_key: 0=did not find key, 1=found key
//   returns 0=succes, otherwise error
// action
//   reads up to max_chars, or until the search_key is encountered
//   (if specified), or until the timeout is reached, whichever
//   happens first.


#define SER_LOG_DBG  0 /* log everything including all char IO  */
#define SER_LOG_WARN 1 /* log warnings, errors, and bugs */
#define SER_LOG_ERR  2 /* log only errors and bugs */
#define SER_LOG_BUG  3 /* logs bugs in the ser.c code, if there are any */


typedef void ser_log_func_t(char *s);
void ser_set_log_func(ser_log_func_t *func, int new_log_lvl);
// desc
//    tells this code the function it should use when logging,
//    so the text can go to the console, or a log file, or whatever.
//    It's best to do this before calling any other ser routines.
//    You only need to do this once.
// inputs
//    func = a pointer to a function of type ser_log_func_t
//    new_log_lvl = one of SER_LOG*.  By default, level is SER_LOG_BUG.
// note: Use of this routine is entirely optional.


void ser_get_last_err(char *buf, int buf_len);
// inputs
//   buf: where to put error message
//   buf_len: max length of error msg
// outputs
//   buf: fills in buf with last error.


#endif
