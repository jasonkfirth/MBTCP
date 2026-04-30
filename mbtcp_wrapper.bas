' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: mbtcp_wrapper.bas
'
' Purpose:
'
'     C wrapper for the Modbus TCP client library.
'
' Responsibilities:
'
'      - Exporting FreeBASIC client functions with C-compatible names.
'      - Handling string and array conversions between C and FreeBASIC.
'
' This file intentionally does NOT contain:
'
'      - Core Modbus protocol logic (delegated to modbustcp.bi).
' -------------------------------------------------------------------------

#include once "modbustcp.bi"

extern "C"

' -------------------------------------------------------------------------
' Connection and Initialization
' -------------------------------------------------------------------------

sub mbtcp_set_port_c cdecl alias "mbtcp_set_port" (byval port as long)
    MBTCP_SetPort(port)
end sub

sub mbtcp_init_c cdecl alias "mbtcp_init" ()
    MBTCP_Init()
end sub

sub mbtcp_connect_c cdecl alias "mbtcp_connect" (byval ip as zstring ptr)
    if ip = 0 then exit sub
    MBTCP_Connect(*ip)
end sub

sub mbtcp_disconnect_c cdecl alias "mbtcp_disconnect" ()
    MBTCP_Disconnect()
end sub

' -------------------------------------------------------------------------
' Data Retrieval
' -------------------------------------------------------------------------

function mbtcp_retrieve_coil_c cdecl alias "mbtcp_retrieve_coil" (byval coil_number as long) as long
    return MBTCP_RetrieveCoil(coil_number)
end function

function mbtcp_retrieve_discrete_input_c cdecl alias "mbtcp_retrieve_discrete_input" (byval coil_number as long) as long
    return MBTCP_RetrieveDiscreteInput(coil_number)
end function

function mbtcp_retrieve_register_c cdecl alias "mbtcp_retrieve_register" (byval reg_number as long) as long
    return MBTCP_RetrieveRegister(reg_number)
end function

function mbtcp_retrieve_input_register_c cdecl alias "mbtcp_retrieve_input_register" (byval reg_number as long) as long
    return MBTCP_RetrieveInputRegister(reg_number)
end function

function mbtcp_retrieve_long_register_c cdecl alias "mbtcp_retrieve_long_register" (byval reg_number as long) as long
    return MBTCP_RetrieveLongRegister(reg_number)
end function

function mbtcp_retrieve_float_register_c cdecl alias "mbtcp_retrieve_float_register" (byval reg_number as long) as single
    return MBTCP_RetrieveFloatRegister(reg_number)
end function

' -------------------------------------------------------------------------
' Data Writing
' -------------------------------------------------------------------------

function mbtcp_write_coil_c cdecl alias "mbtcp_write_coil" (byval value as long, byval coil_number as long) as long
    return MBTCP_WriteCoil(value, coil_number)
end function

function mbtcp_write_register_c cdecl alias "mbtcp_write_register" (byval value as short, byval reg_number as long) as long
    return MBTCP_WriteRegister(value, reg_number)
end function

function mbtcp_write_long_register_c cdecl alias "mbtcp_write_long_register" (byval value as long, byval reg_number as long) as long
    return MBTCP_WriteLongRegister(value, reg_number)
end function

function mbtcp_write_float_register_c cdecl alias "mbtcp_write_float_register" (byval value as single, byval reg_number as long) as long
    return MBTCP_WriteFloatRegister(value, reg_number)
end function

function mbtcp_write_multiple_registers_c cdecl alias "mbtcp_write_multiple_registers" (byval values as ushort ptr, byval count as long, byval start_reg as long) as long
    if values = 0 or count <= 0 then return MBTCP_COMM_ERROR
    dim fb_values(0 to count-1) as ushort
    for i as long = 0 to count-1
        fb_values(i) = values[i]
    next
    return MBTCP_WriteMultipleRegisters(fb_values(), start_reg)
end function

function mbtcp_write_multiple_coils_c cdecl alias "mbtcp_write_multiple_coils" (byval values as ubyte ptr, byval count as long, byval start_coil as long) as long
    if values = 0 or count <= 0 then return MBTCP_COMM_ERROR
    dim fb_values(0 to count-1) as ubyte
    for i as long = 0 to count-1
        fb_values(i) = values[i]
    next
    return MBTCP_WriteMultipleCoils(fb_values(), start_coil)
end function

' -------------------------------------------------------------------------
' Diagnostics and Status
' -------------------------------------------------------------------------

function mbtcp_read_exception_status_c cdecl alias "mbtcp_read_exception_status" () as long
    return MBTCP_ReadExceptionStatus()
end function

function mbtcp_diagnostics_c cdecl alias "mbtcp_diagnostics" (byval sub_func as ushort, byval in_data as ushort, byval out_data as ushort ptr) as long
    dim tmp as ushort
    dim rc as long = MBTCP_Diagnostics(sub_func, in_data, tmp)
    if out_data <> 0 then *out_data = tmp
    return rc
end function

function mbtcp_get_comm_event_counter_c cdecl alias "mbtcp_get_comm_event_counter" (byval out_res as MBTCP_CommEventCounterResult ptr) as long
    if out_res = 0 then return MBTCP_COMM_ERROR
    return MBTCP_GetCommEventCounter(*out_res)
end function

function mbtcp_get_comm_event_log_c cdecl alias "mbtcp_get_comm_event_log" (byval out_res as MBTCP_CommEventLogResult ptr) as long
    if out_res = 0 then return MBTCP_COMM_ERROR
    return MBTCP_GetCommEventLog(*out_res)
end function

function mbtcp_report_server_id_c cdecl alias "mbtcp_report_server_id" (byval out_id as zstring ptr, byval max_len as long) as long
    dim fb_id as string
    dim rc as long = MBTCP_ReportServerID(fb_id)
    if rc = 0 and out_id <> 0 then
        '' Manual string copy helper
        dim length as long = len(fb_id)
        if length >= max_len then length = max_len - 1
        if length < 0 then length = 0
        for i as long = 0 to length - 1
            out_id[i] = fb_id[i]
        next
        out_id[length] = 0
    end if
    return rc
end function

function mbtcp_read_write_multiple_registers_c cdecl alias "mbtcp_read_write_multiple_registers" ( _
    byval read_start as long, _
    byval read_qty as long, _
    byval write_start as long, _
    byval write_values as ushort ptr, _
    byval write_qty as long, _
    byval out_read_values as ushort ptr ) as long

    if write_values = 0 or write_qty <= 0 or out_read_values = 0 then return MBTCP_COMM_ERROR

    dim fb_write_values(0 to write_qty-1) as ushort
    for i as long = 0 to write_qty-1
        fb_write_values(i) = write_values[i]
    next

    dim fb_read_values() as ushort
    dim rc as long = MBTCP_ReadWriteMultipleRegisters(read_start, read_qty, write_start, fb_write_values(), fb_read_values())

    if rc = 0 then
        for i as long = 0 to read_qty-1
            out_read_values[i] = fb_read_values(i)
        next
    end if

    return rc
end function

function mbtcp_mask_write_register_c cdecl alias "mbtcp_mask_write_register" (byval reg_number as long, byval and_mask as ushort, byval or_mask as ushort) as long
    return MBTCP_MaskWriteRegister(reg_number, and_mask, or_mask)
end function

' -------------------------------------------------------------------------
' Global Getters/Setters
' -------------------------------------------------------------------------

sub mbtcp_set_timeout_c cdecl alias "mbtcp_set_timeout" (byval ms as long)
    MBP_RecvTimeoutMS = ms
end sub

function mbtcp_get_timeout_c cdecl alias "mbtcp_get_timeout" () as long
    return MBP_RecvTimeoutMS
end function

sub mbtcp_set_unit_id_c cdecl alias "mbtcp_set_unit_id" (byval id as long)
    MBP_UnitID = id
end sub

function mbtcp_get_unit_id_c cdecl alias "mbtcp_get_unit_id" () as long
    return MBP_UnitID
end function

sub mbtcp_set_zero_offset_c cdecl alias "mbtcp_set_zero_offset" (byval offset as long)
    MBP_ZeroOffset = offset
end sub

function mbtcp_get_zero_offset_c cdecl alias "mbtcp_get_zero_offset" () as long
    return MBP_ZeroOffset
end function

sub mbtcp_get_last_error_c cdecl alias "mbtcp_get_last_error" (byval out_err as zstring ptr, byval max_len as long)
    if out_err <> 0 then
        dim length as long = len(MBP_Common_LastError)
        if length >= max_len then length = max_len - 1
        if length < 0 then length = 0
        for i as long = 0 to length - 1
            out_err[i] = MBP_Common_LastError[i]
        next
        out_err[length] = 0
    end if
end sub

end extern

' end of mbtcp_wrapper.bas
