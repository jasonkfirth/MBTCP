' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: mbtcp_server_wrapper.bas
'
' Purpose:
'
'     C wrapper for the Modbus TCP server library.
'
' Responsibilities:
'
'      - Exporting FreeBASIC server functions with C-compatible names.
'
' This file intentionally does NOT contain:
'
'      - Core Modbus protocol logic (delegated to modbustcp_server.bi).
' -------------------------------------------------------------------------

#include once "modbustcp_server.bi"

extern "C"

' -------------------------------------------------------------------------
' Server Control
' -------------------------------------------------------------------------

sub mbse_init_c cdecl alias "mbse_init" ()
    MBSE_Init()
end sub

sub mbse_shutdown_c cdecl alias "mbse_shutdown" ()
    MBSE_Shutdown()
end sub

function mbse_start_server_c cdecl alias "mbse_start_server" (byval port as long) as long
    return MBSE_StartServer(port)
end function

sub mbse_stop_server_c cdecl alias "mbse_stop_server" ()
    MBSE_StopServer()
end sub

sub mbse_set_server_id_string_c cdecl alias "mbse_set_server_id_string" (byval s as zstring ptr)
    if s <> 0 then
        MBSE_SetServerIDString(*s)
    end if
end sub

' -------------------------------------------------------------------------
' Data Access Functions
' -------------------------------------------------------------------------

sub mbse_write_coil_c cdecl alias "mbse_write_coil" (byval addr as long, byval value as ubyte)
    MBSE_WriteCoil(addr, value)
end sub

function mbse_read_coil_c cdecl alias "mbse_read_coil" (byval addr as long) as ubyte
    return MBSE_ReadCoil(addr)
end function

sub mbse_write_discrete_input_c cdecl alias "mbse_write_discrete_input" (byval addr as long, byval value as ubyte)
    MBSE_WriteDiscreteInput(addr, value)
end sub

function mbse_read_discrete_input_c cdecl alias "mbse_read_discrete_input" (byval addr as long) as ubyte
    return MBSE_ReadDiscreteInput(addr)
end function

sub mbse_write_holding_register_c cdecl alias "mbse_write_holding_register" (byval addr as long, byval value as ushort)
    MBSE_WriteHoldingRegister(addr, value)
end sub

function mbse_read_holding_register_c cdecl alias "mbse_read_holding_register" (byval addr as long) as ushort
    return MBSE_ReadHoldingRegister(addr)
end function

sub mbse_write_input_register_c cdecl alias "mbse_write_input_register" (byval addr as long, byval value as ushort)
    MBSE_WriteInputRegister(addr, value)
end sub

function mbse_read_input_register_c cdecl alias "mbse_read_input_register" (byval addr as long) as ushort
    return MBSE_ReadInputRegister(addr)
end function

sub mbse_write_long_c cdecl alias "mbse_write_long" (byval addr as long, byval value as long)
    MBSE_WriteLong(addr, value)
end sub

function mbse_read_long_c cdecl alias "mbse_read_long" (byval addr as long) as long
    return MBSE_ReadLong(addr)
end function

sub mbse_write_float_c cdecl alias "mbse_write_float" (byval addr as long, byval value as single)
    MBSE_WriteFloat(addr, value)
end sub

function mbse_read_float_c cdecl alias "mbse_read_float" (byval addr as long) as single
    return MBSE_ReadFloat(addr)
end function

sub mbse_write_input_long_c cdecl alias "mbse_write_input_long" (byval addr as long, byval value as long)
    MBSE_WriteInputLong(addr, value)
end sub

function mbse_read_input_long_c cdecl alias "mbse_read_input_long" (byval addr as long) as long
    return MBSE_ReadInputLong(addr)
end function

sub mbse_write_input_float_c cdecl alias "mbse_write_input_float" (byval addr as long, byval value as single)
    MBSE_WriteInputFloat(addr, value)
end sub

function mbse_read_input_float_c cdecl alias "mbse_read_input_float" (byval addr as long) as single
    return MBSE_ReadInputFloat(addr)
end function

' -------------------------------------------------------------------------
' Config Getters/Setters
' -------------------------------------------------------------------------

sub mbse_set_strict_unit_id_c cdecl alias "mbse_set_strict_unit_id" (byval strict as long)
    MBSE_StrictUnitID = strict
end sub

sub mbse_set_expected_unit_id_c cdecl alias "mbse_set_expected_unit_id" (byval id as ubyte)
    MBSE_ExpectedUnitID = id
end sub

sub mbse_set_addr_ceiling_c cdecl alias "mbse_set_addr_ceiling" (byval ceiling as long)
    MBSE_AddrCeiling = ceiling
end sub

sub mbse_set_client_timeouts_c cdecl alias "mbse_set_client_timeouts" (byval recv_ms as long, byval send_ms as long)
    MBSE_ClientRecvTimeoutMS = recv_ms
    MBSE_ClientSendTimeoutMS = send_ms
end sub

function mbse_get_client_count_c cdecl alias "mbse_get_client_count" () as long
    return MBSE_ClientCount
end function

end extern

' end of mbtcp_server_wrapper.bas
