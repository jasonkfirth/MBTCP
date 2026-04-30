' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: fix_errno.bi
'
' Purpose:
'
'     Define missing errno constants for compatibility.
'
' Responsibilities:
'
'      - Providing definitions for EWOULDBLOCK and ETIMEDOUT if missing.
'
' This file intentionally does NOT contain:
'
'      - Any protocol or logic.
' -------------------------------------------------------------------------

#ifndef EWOULDBLOCK
#define EWOULDBLOCK 11
#endif
#ifndef ETIMEDOUT
#define ETIMEDOUT 110
#endif

' end of fix_errno.bi
