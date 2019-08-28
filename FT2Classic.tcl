package provide Ixia 1.0

global env
source $env(IXIA_LIB)
source $env(ixTclNetwork)/pkgIndex.tcl
if {[info exists env(IxiaLibPath)]} {
    set path $env(IxiaLibPath)
}
if {[info exist env(clear_stats)]} {
    set apiData(clear_stats) $env(clear_stats)
}

namespace eval ixia {
    set ::ixia::TclInterp [interp create classic]
    interp eval $::ixia::TclInterp "package require Ixia"
    package require IxTclNetwork
}
array set apiData {}
global env
global stream_name
set stream_name 1

if {[info exist env(ixnetwork_tcl_server)]} {
    set apiData(tcl_server) $env(ixnetwork_tcl_server)
} else {
    error "no tcl_server value given. please set it in env variable \"ixnetwork_tcl_server \""
}

proc debug_old {{s {}}} {
    if ![info exists ::bp_skip] {
        set ::bp_skip [list]
    } elseif {[lsearch -exact $::bp_skip $s]>=0} return
        if [catch {info level -1} who] {set who ::}
    while 1 {
        ##puts -nonewline "$who/$s> "; flush stdout
        #puts -nonewline "$s> "; flush stdout
        gets stdin line
        if {$line=="c"} {#puts "continuing.."; break}
        if {$line=="i"} {set line "info locals"}
        if {$line=="e"} {set line "exit 1"}
        catch {uplevel 1 $line} res
        #puts $res
    }
}

proc expand_ipv6 {args} {
    set ipAddress $args
    if {[regexp -nocase {^([a-fA-F0-9]+)::([a-fA-F0-9]+)$} $ipAddress match m11 m12]} {
           set ipAddress $m11:0:0:0:0:0:0:$m12
    } elseif {[regexp -nocase {^([a-fA-F0-9]+):([a-fA-F0-9]+)::([a-fA-F0-9]+)$} $ipAddress match m1 m2 m3]} {
           set ipAddress $m1:$m2:0:0:0:0:0:$m3
    } elseif {[regexp -nocase {^([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+)::([a-fA-F0-9]+)$} $ipAddress match  m1 m2 m3 m4]} {
           set ipAddress $m1:$m2:$m3:0:0:0:0:$m4
    } elseif {[regexp -nocase {^([a-fA-F0-9]+):([a-fA-F0-9]+)::([a-fA-F0-9]+):([a-fA-F0-9]+)$} $ipAddress match  m1 m2 m3 m4]} {
           set ipAddress $m1:$m2:0:0:0:0:$m3:$m4
    } else {
           set ipAddress $ipAddress
    }
    return $ipAddress
}

proc get_emulation_handle_ipv6 {ipAddress } {

    #package require IxTclNetwork
    set vports [interp eval $::ixia::TclInterp " ixNet getList [ixNet getRoot] vport "]

    set handle_list ""

    foreach vport_handle $vports {
        set interfaces [interp eval $::ixia::TclInterp " ixNet getList $vport_handle interface"]
        if {![string match $interfaces ""]} {
            foreach intf $interfaces {
               set val [catch {interp eval $::ixia::TclInterp " ixNet getA $intf/ipv6:1 -ip " } getIp]
               if {[regexp -nocase {is null} $getIp match]} { 
                    #puts "ip is null"
               } else {

                    if {[string match $getIp [expand_ipv6 $ipAddress]]} {
                        #puts "appending handle $intf"
                        lappend handle_list $intf
                    }
               }
            }
        }

        set route_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/ospf router"]
        if {![string match $route_handles ""]} {
            foreach rthdl $route_handles {
                set routeRanges_hdls [interp eval $::ixia::TclInterp " ixNet getL $rthdl routeRange"]
                if {![string match $routeRanges_hdls ""]} {
                    foreach rtRangeHdl $routeRanges_hdls {
                        set getIp [interp eval $::ixia::TclInterp " ixNet getA $rtRangeHdl -networkNumber"]
                        if {[string match $getIp [expand_ipv6 $ipAddress]]} {
                            lappend handle_list $rtRangeHdl
                        }
                    }
                }
            }
        }

        set route_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/isis router"]
        if {![string match $route_handles ""]} {
            foreach rthdl $route_handles {
                set routeRanges_hdls [interp eval $::ixia::TclInterp " ixNet getL $rthdl routeRange"]
                if {![string match $routeRanges_hdls ""]} {
                    foreach rtRangeHdl $routeRanges_hdls {
                        set getIp [interp eval $::ixia::TclInterp " ixNet getA $rtRangeHdl -firstRoute"]
                        if {[string match $getIp [expand_ipv6 $ipAddress]]} {
                            lappend handle_list $rtRangeHdl
                        }
                    }
                }
            }
        }


        set route_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/bgp neighborRange"]
        if {![string match $route_handles ""]} {
            foreach rthdl $route_handles {
                set routeRanges_hdls [interp eval $::ixia::TclInterp " ixNet getL $rthdl routeRange"]
                if {![string match $routeRanges_hdls ""]} {
                    foreach rtRangeHdl $routeRanges_hdls {
                        set getIp [interp eval $::ixia::TclInterp " ixNet getA $rtRangeHdl -networkAddress"]
                        if {[string match $getIp [expand_ipv6 $ipAddress]]} {
                            lappend handle_list $rtRangeHdl
                        }
                    }
                }
            }
        }
    }
    return $handle_list
}

proc get_emulation_handle {ipAddress } {

    #package require IxTclNetwork
    set vports [interp eval $::ixia::TclInterp " ixNet getList [ixNet getRoot] vport "]
    
    set handle_list ""

    foreach vport_handle $vports {
        set interfaces [interp eval $::ixia::TclInterp " ixNet getList $vport_handle interface"]
        if {![string match $interfaces ""]} {
            foreach intf $interfaces {
               set getIp [interp eval $::ixia::TclInterp " ixNet getA $intf/ipv4 -ip "]
               if {[string match $getIp $ipAddress]} {
                    lappend handle_list $intf
               }
            }
        }
        
        set route_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/ospf router"]
        if {![string match $route_handles ""]} {
            foreach rthdl $route_handles {
                set routeRanges_hdls [interp eval $::ixia::TclInterp " ixNet getL $rthdl routeRange"]
                if {![string match $routeRanges_hdls ""]} {
                    foreach rtRangeHdl $routeRanges_hdls {
                        set getIp [interp eval $::ixia::TclInterp " ixNet getA $rtRangeHdl -networkNumber"]
                        if {[string match $getIp $ipAddress]} {
                            lappend handle_list $rtRangeHdl
                        }
                    }
                }
            }
        }

        set route_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/isis router"]
        if {![string match $route_handles ""]} {
            foreach rthdl $route_handles {
                set routeRanges_hdls [interp eval $::ixia::TclInterp " ixNet getL $rthdl routeRange"]
                if {![string match $routeRanges_hdls ""]} {
                    foreach rtRangeHdl $routeRanges_hdls {
                        set getIp [interp eval $::ixia::TclInterp " ixNet getA $rtRangeHdl -firstRoute"]
                        if {[string match $getIp $ipAddress]} {
                            #puts "getting handle"    
                            lappend handle_list $rtRangeHdl
                        }
                    }
                }
            }
        }


        set route_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/bgp neighborRange"]
        if {![string match $route_handles ""]} {
            foreach rthdl $route_handles {
                set routeRanges_hdls [interp eval $::ixia::TclInterp " ixNet getL $rthdl routeRange"]
                if {![string match $routeRanges_hdls ""]} {
                    foreach rtRangeHdl $routeRanges_hdls {
                        set getIp [interp eval $::ixia::TclInterp " ixNet getA $rtRangeHdl -networkAddress"]
                        if {[string match $getIp $ipAddress]} {
                            lappend handle_list $rtRangeHdl
                        }
                    }
                }
            }
        }
        
        set igmp_host_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/igmp host"]
        if {![string match $igmp_host_handles ""]} {
            foreach igmp_handle $igmp_host_handles {
                set igmp_group_handles [interp eval $::ixia::TclInterp " ixNet getL $igmp_handle group"]
                if {![string match $igmp_group_handles ""]} {
                    foreach igmp_group_handle $igmp_group_handles {
                        set getIp [interp eval $::ixia::TclInterp " ixNet getA $igmp_group_handles -groupFrom"]
                        if {[string match $getIp $ipAddress]} {
                            lappend handle_list $igmp_group_handles
                        }
                    }
                }
            }
        }
        set igmp_querier_handles [interp eval $::ixia::TclInterp " ixNet getL $vport_handle/protocols/igmp querier"]
        if {![string match $igmp_querier_handles ""]} {
            foreach igmp_querier_handle $igmp_querier_handles {
                 set getIp [interp eval $::ixia::TclInterp " ixNet getA $igmp_querier_handle -querierAddress"]
                 if {[string match $getIp $ipAddress]} {
                           lappend handle_list $igmp_querier_handle
                 }
             }
        }
    }
    return $handle_list
}

proc mcastIPv6ToMac { mcastIP } {

    set mcastMac 0000.0000.0000
    set mcastIP [get_ipv6_full_add $mcastIP]
    if { ![ regexp  {([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+)} \
        $mcastIP dump oct1 oct2 oct3 oct4 oct5 oct6 oct7 oct8] } {
        puts "invalid ip format"
        return $mcastMac
    }
    
    if { [expr 0x$oct1] < 65281 || [expr 0x$oct1] > 65535 } {
        puts "invlaid mcast IPv6"
        return $mcastMac
    }
    catch { unset mcastMac }

    set oct7 [format "%04s" $oct7]
    set oct8 [format "%04s" $oct8]
    lappend mcastMac 3333 $oct7 $oct8
    regsub -all { } $mcastMac {.} mcastMac

    return $mcastMac
}

proc get_ipv6_full_add { add } {
    set ipv6_split [split $add ":"]
    set no_hex 1
    foreach hex $ipv6_split {
        if {$no_hex < 8 && $hex != ""} {
            incr no_hex
            append full_add "$hex:"
        } elseif {$hex == ""} {
            set empty_idx [lsearch $ipv6_split ""]
            set length [llength $ipv6_split]
            set rem_hex [expr [expr $length - $empty_idx] - 1]
            for {set i $empty_idx} {$i < [expr 8-$rem_hex]} {incr i} {
                incr no_hex
                append full_add "0:"
            }
            if {$rem_hex == 1 && \
                [lindex $ipv6_split [expr $length-1]] == ""} {
                append full_add "0"
                break
            }
        } else {
            append full_add "$hex"
        }
    }
    return $full_add
}

proc Parse_Dashed_Args {args} {
    global apiData
    set parse_args ""
    regsub -all  "^{|}$"  $args "" args
    set args [split $args " "]
    for { set i 0 } { $i < [llength $args]} { incr i } {
        set arg [lindex $args $i]
        if  {$arg != ""} {
                set arg [string trim $arg]
                switch -regexp -- $arg {
                        "-reset|-arp" {
                                if {[regexp -nocase "^-" [lindex $args [expr $i + 1]] match]} {
                                        set $arg "1"
                                        append parse_args " " "$arg 1"
                                } else {
                                        append parse_args " " $arg
                                }
                        }
                        default {
                                append parse_args " " "$arg"
                        }
                }
        }
    }
    set parse_args  [lsearch -all -inline -not -exact $parse_args {}]
    set key ""
    set val ""
    foreach ele $parse_args {
                if {[string equal $ele {}]} {
                        continue
                }

                if {[regexp -nocase "^-" $ele]} {
                        if {![string equal $key ""]} {
                                keylset apiData(parse_args) $key $val
                                set key ""
                                set val ""
                        }
                }
                if {[regexp -nocase "^-" $ele]} {
                        set key $ele
                } else {
                        lappend val $ele
                }
    }
    keylset apiData(parse_args) $key $val

    return $parse_args
}


proc ::ixia::executeInChild {args} {
    set api [lindex $args 0]
    set args [lindex $args 1]
    return [interp eval $::ixia::TclInterp "::ixia::$api $args"]
}

proc ::ixia::emulation_oam_config_msg {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "emulation_oam_config_msg $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_client_global_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "fc_client_global_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rsvp_tunnel_config {args} {
    set api "emulation_rsvp_tunnel_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_eigrp_config {args} {
    set api "emulation_eigrp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::uds_filter_pallette_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "uds_filter_pallette_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_stp_control {args} {
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_stp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_efm_config {args} {
    set api "emulation_efm_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::interface_config {args} {
    puts "inside wrapper ::ixia::interface_config"
    global apiData
    set args1 $args
    Convert_List_To_Keyedlist $args1
    #puts "inside wrapper ::ixia::interface_config"
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split3_width'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split3_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'integrity_signature'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pcs_marker_fields'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'qos_byte_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split1_mask'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'signature_start_offset'}
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    
    
    # #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'qos_stats'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split3_mask'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'rpr_hec_seed'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'signature_mask'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split2_width'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'tx_lanes'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'qos_pattern_mask'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split3_offset_from'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'sequence_num_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'router_solicitation_retries'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'integrity_signature_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'signature_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pcs_period'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'signature'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_mask'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split2_offset_from'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pcs_sync_bits'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'qos_pattern_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split1_offset_from'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'sequence_checking'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'bert_configuration'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split2_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pcs_period_type'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'qos_packet_type'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_split2_mask'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pgid_128k_bin_enable'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pcs_repeat'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'bert_error_insertion'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'no_write'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pcs_lane'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'qos_pattern_match'}
    if {[lsearch $args "-ipv4_prefix_length"] != -1} {
        set ipv4_length [keylget apiData(expArgs) -ipv4_prefix_length]
        set ipv4PrefixLength [ subnetmaskToCIDR $ipv4_length ]
        keyldel apiData(expArgs) -ipv4_prefix_length
        set args [Convert_Keyedlist_To_List $apiData(expArgs)]
        lappend args -ipv4_prefix_length $ipv4PrefixLength
    }
	
	if {[lsearch $args "-signature"] != -1} {
           keyldel apiData(expArgs) -signature
    	}
	if {[lsearch $args "-signature_offset"] != -1} {
           keyldel apiData(expArgs) -signature_offset
    	}
	if {[lsearch $args "-pgid_mode"] != -1} {
		set pgid_mode [keylget apiData(expArgs) -pgid_mode]
		if {[string equal $pgid_mode "custom"]} {
		keyldel apiData(expArgs) -pgid_mode
               }
	}
	if {[lsearch $args "-pgid_offset"] != -1} {
		    set pgid_offset [keylget apiData(expArgs) -pgid_offset]
		    keyldel apiData(expArgs) -pgid_offset
               }

    set args [Convert_Keyedlist_To_List $apiData(expArgs)]
	
    if {[lsearch $args "-gateway"] == -1} {
       if {[lsearch $args "-intf_ip_addr"] != -1} {
           set ipv4Address [keylget apiData(expArgs) -intf_ip_addr]
           regexp -nocase {^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$} $ipv4Address match m1 m2 m3 m4
           set m5 [expr $m4-1]
           set gatewayIp $m1.$m2.$m3.$m5
           lappend args -gateway $gatewayIp
       }
    }
    if {[lsearch $args "-ipv6_gateway"] == -1} {
       if {[lsearch $args "-ipv6_intf_addr"] != -1} {
           set ipv6Address [keylget apiData(expArgs) -ipv6_intf_addr]
           set ipv6 [expand_ipv6 $ipv6Address]
           regexp -nocase {^([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+)$} $ipv6 match m1 m2 m3 m4 m5 m6 m7 m8
           if {$m8 == 1} {
              set m9 [expr $m8+1]
              set gatewayIp $m1:$m2:$m3:$m4:$m5:$m6:$m7:$m9
              lappend args -ipv6_gateway $gatewayIp
           } else {
              set m9 [expr $m8-1]
              set gatewayIp $m1:$m2:$m3:$m4:$m5:$m6:$m7:$m9
              lappend args -ipv6_gateway $gatewayIp
           }
       }
    }
    if {[lsearch $args "-arp_send_req"] != -1} {
       if {[lsearch $args "-arp"] == -1} {
           lappend args -arp 1
       }
       if {[lsearch $args "-arp_on_linkup"] == -1} {
           lappend args -arp_on_linkup 1
       }
       if {[lsearch $args "-arp_req_retries"] == -1} {
           lappend args -arp_req_retries ""
       }
       if {[lsearch $args "-arp_refresh_interval"] == -1} {
           lappend args -arp_refresh_interval 60 
       }
    }
    puts $args
    set api "interface_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_cfm_links_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_cfm_links_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_stp_bridge_config {args} {
    #Body { Arguments with no mandatory tag argument 'auto_pick_bridge_mac'}
    #Body { Arguments with no mandatory tag argument 'port_no_intf_step'}
    #Body { Arguments with no mandatory tag argument 'cst_root_priority'}
    #Body { Arguments with no mandatory tag argument 'jitter_percentage'}
    #Body { Arguments with no mandatory tag argument 'cist_reg_root_mac'}
    #Body { Arguments with no mandatory tag argument 'intf_ipv6_addr'}
    #Body { Arguments with no mandatory tag argument 'cist_external_root_priority'}
    #Body { Arguments with no mandatory tag argument 'intf_ip_addr_bridge_step'}
    #Body { Arguments with no mandatory tag argument 'max_age'}
    #Body { Arguments with no mandatory tag argument 'intf_count'}
    #Body { Arguments with no mandatory tag argument 'auto_pick_port'}
    #Body { Arguments with no mandatory tag argument 'override_tracking'}
    #Body { Arguments with no mandatory tag argument 'root_priority'}
    #Body { Arguments with no mandatory tag argument 'inter_bdpu_gap'}
    #Body { Arguments with no mandatory tag argument 'vlan_user_priority'}
    #Body { Arguments with no mandatory tag argument 'count'}
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'bridge_mac_step'}
    #Body { Arguments with no mandatory tag argument 'bridge_priority'}
    #Body { Arguments with no mandatory tag argument 'cist_external_root_mac'}
    #Body { Arguments with no mandatory tag argument 'port_priority'}
    #Body { Arguments with no mandatory tag argument 'mstc_name'}
    #Body { Arguments with no mandatory tag argument 'intf_ip_addr_step'}
    #Body { Arguments with no mandatory tag argument 'bridge_msti_vlan'}
    #Body { Arguments with no mandatory tag argument 'intf_ipv6_addr_bridge_step'}
    #Body { Arguments with no mandatory tag argument 'mstc_revision'}
    #Body { Arguments with no mandatory tag argument 'port_no'}
    #Body { Arguments with no mandatory tag argument 'reset'}
    #Body { Arguments with no mandatory tag argument 'mac_address_init'}
    #Body { Arguments with no mandatory tag argument 'message_age'}
    #Body { Arguments with no mandatory tag argument 'cist_remaining_hop'}
    #Body { Arguments with no mandatory tag argument 'mtu'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    #Body { Arguments with no mandatory tag argument 'cist_reg_root_cost'}
    #Body { Arguments with no mandatory tag argument 'cist_external_root_cost'}
    #Body { Arguments with no mandatory tag argument 'bridge_mac'}
    #Body { Arguments with no mandatory tag argument 'intf_gw_ip_addr_step'}
    #Body { Arguments with no mandatory tag argument 'override_existence_check'}
    #Body { Arguments with no mandatory tag argument 'intf_ip_addr'}
    #Body { Arguments with no mandatory tag argument 'port_no_bridge_step'}
    #Body { Arguments with no mandatory tag argument 'hello_interval'}
    #Body { Arguments with no mandatory tag argument 'cist_reg_root_priority'}
    #Body { Arguments with no mandatory tag argument 'mac_address_bridge_step'}
    #Body { Arguments with no mandatory tag argument 'intf_ipv6_addr_step'}
    #Body { Arguments with no mandatory tag argument 'port_handle'}
    #Body { Arguments with no mandatory tag argument 'bridge_system_id'}
    #Body { Arguments with no mandatory tag argument 'root_cost'}
    #Body { Arguments with no mandatory tag argument 'vlan_id'}
    #Body { Arguments with no mandatory tag argument 'cst_root_path_cost'}
    #Body { Arguments with no mandatory tag argument 'link_type'}
    #Body { Arguments with no mandatory tag argument 'enable_jitter'}
    #Body { Arguments with no mandatory tag argument 'root_mac'}
    #Body { Arguments with no mandatory tag argument 'vlan_id_intf_step'}
    #Body { Arguments with no mandatory tag argument 'cst_root_mac_address'}
    #Body { Arguments with no mandatory tag argument 'root_system_id'}
    #Body { Arguments with no mandatory tag argument 'vlan'}
    #Body { Arguments with no mandatory tag argument 'intf_cost'}
    #Body { Arguments with no mandatory tag argument 'cst_vlan_port_priority'}
    #Body { Arguments with no mandatory tag argument 'intf_ip_prefix_length'}
    #Body { Arguments with no mandatory tag argument 'vlan_id_bridge_step'}
    #Body { Arguments with no mandatory tag argument 'intf_ipv6_prefix_length'}
    #Body { Arguments with no mandatory tag argument 'intf_gw_ip_addr'}
    #Body { Arguments with no mandatory tag argument 'interface_handle'}
    #Body { Arguments with no mandatory tag argument 'pvid'}
    #Body { Arguments with no mandatory tag argument 'mac_address_intf_step'}
    #Body { Arguments with no mandatory tag argument 'intf_gw_ip_addr_bridge_step'}
    #Body { Arguments with no mandatory tag argument 'vlan_user_priority_bridge_step'}
    #Body { Arguments with no mandatory tag argument 'bridge_mode'}
    #Body { Arguments with no mandatory tag argument 'forward_delay'}
    set api "emulation_stp_bridge_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_cfm_custom_tlv_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_cfm_custom_tlv_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pbb_info {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_pbb_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_igmp_info {args} {
    set api "emulation_igmp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::get_nodrop_rate {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'run_time_sec'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'stream_mode'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'min_percent'}
    #Body { Need to fill equivalent logic in classic for FT Mandatory argument 'max_rate'}
    #Body { Need to fill equivalent logic in classic for FT Mandatory argument 'rx_port_handle'}
    #Body { Need to fill equivalent logic in classic for FT Mandatory argument 'stream_id'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'poll_timeout_sec'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'tolerance'}
    #Body { Need to fill equivalent logic in classic for FT Mandatory argument 'tx_port_handle'}
    set api "get_nodrop_rate $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_bgp_config {args} {
    global apiData
    set args1 $args
    Convert_List_To_Keyedlist $args1
    if {[lsearch $args "-mac_address_start"] != -1} {
        puts "removing -mac_address_start"
        keyldel apiData(expArgs) -mac_address_start 
    }
    set args [Convert_Keyedlist_To_List $apiData(expArgs)]

#    if {[lsearch $args "-port_handle"] != -1} {
#        set portList [keylget apiData(expArgs) -port_handle]
#        if {[llength $portList] > 1} {
#           puts "remove port_handle"
#           #set args [lreplace $args [lsearch $args $i] [lsearch $args $i]+1]
#           #interpreter
#           #set args [lreplace $args [lsearch $args "-port_handle"] [lsearch $args "-port_handle"]+1]
#           set args [lreplace $args [lsearch $args "-port_handle"] [expr {[lsearch $args "-port_handle"] + 1}]]
#           set port [lindex $portList 0]
#           lappend args -port_handle $port
#           set api "emulation_bgp_config $args"
#           return [::ixia::executeInChild $api]
#        } else {
#
#            if {[lsearch $args "-mac_address_start"] != -1} {
#                set srcmac [keylget apiData(expArgs) -mac_address_start]
#                set api "interface_config -mode destroy -src_mac_addr $srcmac -port_handle $portList"
#                puts "interface_config destroy is $api"
#                set ret [::ixia::executeInChild $api]
#                puts "return is $ret"
#
#            }


            set api "emulation_bgp_config $args"
            return [::ixia::executeInChild $api]
#        }
#    }
}

proc ::ixia::emulation_igmp_config {args} {
#    puts "inside wrapper ::ixia::emulation_config"
#    global apiData
#    set args1 $args
#    Convert_List_To_Keyedlist $args
#    if {[lsearch $args -ipv4_prefix_length ] != -1} {
#         set args [lremove  $args -ipv4_prefix_length]

#    }
    puts $args
    global apiData
	if {[lsearch $args "-intf_prefix_len"] != -1} {
        Convert_List_To_Keyedlist $args
        set intf_len [keylget apiData(expArgs) -intf_prefix_len]
        set intfPrefixLen [ subnetmaskToCIDR $intf_len ]
        keyldel apiData(expArgs) -intf_prefix_len
        set args [Convert_Keyedlist_To_List $apiData(expArgs)]
        lappend args -intf_prefix_len $intfPrefixLen
    }
	
    if {[lsearch $args "-ipv4_prefix_length"] != -1} {
        Convert_List_To_Keyedlist $args
        set ipv4_length [keylget apiData(expArgs) -ipv4_prefix_length]
        set ipv4PrefixLength [ subnetmaskToCIDR $ipv4_length ]
        keyldel apiData(expArgs) -ipv4_prefix_length
        set args [Convert_Keyedlist_To_List $apiData(expArgs)]
        lappend args -ipv4_prefix_length $ipv4PrefixLength
    }
	set args1 $args
    Convert_List_To_Keyedlist $args1
    if {[lsearch $args "-igmp_version"] !=-1} {
        set igmp_version [keylget apiData(expArgs) -igmp_version]
    	if {[string match $igmp_version "v3"]} {
    		if {[lsearch $args "-filter_mode"] == -1} {
    			lappend args -filter_mode include
    		}
	}		
      }	
	  
	if {[lsearch $args "-unsolicited_report_interval"] == -1} {
           lappend args -unsolicited_report_interval 120
       }
	 if {[lsearch $args "-ip_router_alert"] == -1} {
           lappend args -ip_router_alert 1
       } else {
	   set ip_router_alert [keylget apiData(expArgs) -ip_router_alert]
	   if {[string match $ip_router_alert 0]} {
	       Convert_List_To_Keyedlist $args
	       keyldel apiData(expArgs) -ip_router_alert
	       set args [Convert_Keyedlist_To_List $apiData(expArgs)]
	       lappend args -ip_router_alert 1
	   }
       }

    set api "emulation_igmp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_dhcp_control {args} {
    set api "emulation_dhcp_control $args"
   return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_isis_control {args} {
    set api "emulation_isis_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::interface_stats {args} {
    #Body { Arguments with no mandatory tag argument 'port_handle'}
    set api "interface_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_multicast_source_config {args} {
    set api "emulation_multicast_source_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_multicast_group_config {args} {
    set api "emulation_multicast_group_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::cleanup_session {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'reset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'port_handle'}
    set api "cleanup_session $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ospf_lsa_config {args} {
    set api "emulation_ospf_lsa_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_eigrp_control {args} {
    set api "emulation_eigrp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::vport_info {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "vport_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_bgp_control {args} {
    set api "emulation_bgp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rsvp_control {args} {
    set api "emulation_rsvp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ospf_topology_route_config {args} {
    global apiData
    set args_list [Parse_Dashed_Args $args]
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    } else {
        set mod [keylget apiData(parse_args) -mode]
        if {[string equal "create" $mod]} {
            if {[lsearch $args "-type"] == -1} {
                error "Missing Mandatory Argument \"-type\""
            }
            if {[lsearch $args "-handle"] == -1} {
                error "Missing Mandatory Argument \"handle\""
            }
        } elseif {[string equal "modify" $mod] || [string equal "enable" $mod] || [string equal "disable" $mod]} {
            if {[lsearch $args "-type"] == -1} {
                error "Missing Mandatory Argument \"-type\""
            }
            if {[lsearch $args "-handle"] == -1} {
                error "Missing Mandatory Argument \"handle\""
            }
            if {[lsearch $args "-elem_handle"] == -1} {
                error "Missing Mandatory Argument \"elem_handle\""
            }
            
        } elseif {[string equal "delete" $mod]} {
            if {[lsearch $args "-handle"] == -1} {
                error "Missing Mandatory Argument \"handle\""
            }
            if {[lsearch $args "-elem_handle"] == -1} {
                error "Missing Mandatory Argument \"elem_handle\""
            }
        }
    }        
    set api "emulation_ospf_topology_route_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::packet_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'packet_type'
    if {[lsearch $args "-packet_type"] == -1} {
        #error "Missing Mandatory Argument \"packet_type\""
	lappend args -packet_type both
    }
    set api "packet_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::traffic_stats {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_counter_vci_data_item_list'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_counter_vpi_type'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_counter_vpi_mode'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_reassembly_enable_iptcpudp_checksum'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_reassembly_encapsulation'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vpi'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_counter_vci_mode'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_counter_vpi_data_item_list'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_reassembly_enable_ip_qos'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'ignore_rate'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'qos_stats'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci_count'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vpi_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'packet_group_id'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_counter_vci_type'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci'}
    sleep 30
    global env
    if {[info exists env(findNdr)]} {
	   set findndr $env(findNdr)
    } else {
           set findndr ""
    }
    global apiData
    set args2 $args
    Convert_List_To_Keyedlist $args2
   set pgidStr "pgid"
    if {[lsearch $args "-packet_group_id"] != -1} {
	 set pgid [expr [keylget apiData(expArgs) -packet_group_id]-1]
         puts "pgid: $pgid"
	 puts "Removing -packet_group_id "
	 keyldel apiData(expArgs) -packet_group_id 
	 set pgidStr "pgid"
    }
    set api "traffic_stats $args"
    set stats [::ixia::executeInChild $api]
    set ports [list [keylget apiData(expArgs) -port_handle]]
    regsub -all "{" $ports {} ports
    regsub -all "}" $ports {} ports
    set portLength [llength $ports]
    set i 1
    foreach port $ports {
	if {[catch {keylget stats $port.aggregate.rx.pkt_count} errmsg]} {
		puts "This port dont have pkt_count: $port"
		#keylset stats $port.aggregate.rx.uds1_count "NA"
	} else {
		set pkts [keylget stats $port.aggregate.rx.pkt_count]
		keylset stats $port.aggregate.rx.uds1_count $pkts
		sleep 5
	}
	if {[catch {keylget apiData(expArgs) -mode} errmsg]} {
		puts "Traffic stats doesn't have mode param"
	} else {
		set mod [keylget apiData(expArgs) -mode]
		if {[string equal $mod "stream"]} {
			if {[string match $findndr "ndr"]} {
				set streamValues [keylget stats $port.stream]
				foreach  streamValue $streamValues {
					set value [lindex $streamValue 0]
					break
				}
				if {$i<=$portLength} {
					set newValue [string trim $value]
					regsub -all "$newValue" $stats $i stats
					set i [expr {$i + 1}]
				}						
			} 
			if {[string equal "pgid" $pgidStr]} {
			    set streamValues [keylget stats $port.stream]
			    foreach  streamValue $streamValues {
				set value [lindex $streamValue 0]
				break
			    }
			    set newValue [string trim $value]
			    if {[catch {keylget stats $port.stream.$newValue.rx.total_pkts} errmsg]} {
				    puts "This port $port not have rx details"
		            } else {
			         set pktCount [keylget stats $port.stream.$newValue.rx.total_pkts]
			         keylset stats $port.$pgidStr.rx.pkt_count.$pgid $pktCount
			    }
			}
		}
	}  
    }		
    if {[catch {keylget stats aggregate.rx.uds1_frame_count.max} errmsg]} {
	puts "Traffic stats doesn't have User Defined stats"
    } else {
	set udsmin [keylget stats aggregate.rx.data_int_frames_count.min]
	set udsmax [keylget stats aggregate.rx.data_int_frames_count.max]
        set udsavg [keylget stats aggregate.rx.data_int_frames_count.avg]
	set uds1max [keylget stats aggregate.rx.uds1_frame_count.max]
	if {[string equal $uds1max "0"]} {
	    keylset stats aggregate.rx.uds1_frame_count.min $udsmin
            keylset stats aggregate.rx.uds1_frame_count.max $udsmax
	    keylset stats aggregate.rx.uds1_frame_count.avg $udsavg
	}
    }
    if {0} {
       if {[catch {keylget stats $port.aggregate.rx.uds2_frame_count} errmsg]} {
           puts "This port dont have uds2_frame_count: $port"
           #set udsCount [keylget stats $port.aggregate.rx.uds2_frame_count]
           keylset stats $port.aggregate.rx.uds_count2 "NA"	
       } else {
         	set udsCount [keylget stats $port.aggregate.rx.uds2_frame_count]
                keylset stats $port.aggregate.rx.uds_count2 $udsCount
       }
    }
    return $stats
}

proc ::ixia::emulation_twamp_test_range_config {args} {
    set api "emulation_twamp_test_range_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::pppox_control {args} {
    set api "pppox_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_stp_msti_config {args} {
    #Body { Arguments with no mandatory tag argument 'msti_mac_step'}
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'msti_vlan_stop_step'}
    #Body { Arguments with no mandatory tag argument 'msti_vlan_start_step'}
    #Body { Arguments with no mandatory tag argument 'msti_vlan_start'}
    #Body { Arguments with no mandatory tag argument 'msti_wildcard_percent_start'}
    #Body { Arguments with no mandatory tag argument 'msti_internal_root_path_cost'}
    #Body { Arguments with no mandatory tag argument 'msti_wildcard_percent_enable'}
    #Body { Arguments with no mandatory tag argument 'count'}
    #Body { Arguments with no mandatory tag argument 'msti_id'}
    #Body { Arguments with no mandatory tag argument 'msti_mac'}
    #Body { Arguments with no mandatory tag argument 'msti_hops'}
    #Body { Arguments with no mandatory tag argument 'msti_port_priority'}
    #Body { Arguments with no mandatory tag argument 'msti_id_step'}
    #Body { Arguments with no mandatory tag argument 'msti_vlan_stop'}
    #Body { Arguments with no mandatory tag argument 'bridge_handle'}
    #Body { Arguments with no mandatory tag argument 'msti_priority'}
    #Body { Arguments with no mandatory tag argument 'msti_name'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_stp_msti_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_fport_options_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "fc_fport_options_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::pppox_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'protocol'
    if {[lsearch $args "-protocol"] == -1} {
        error "Missing Mandatory Argument \"protocol\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'encap'
    if {[lsearch $args "-encap"] == -1} {
        error "Missing Mandatory Argument \"encap\""
    }
    set api "pppox_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ospf_control {args} {
    set api "emulation_ospf_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_bfd_config {args} {
    set api "emulation_bfd_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_oam_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'action'
    if {[lsearch $args "-action"] == -1} {
        error "Missing Mandatory Argument \"action\""
    }
    set api "emulation_oam_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_efm_stat {args} {
    set api "emulation_efm_stat $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ospf_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'intf_ip_addr_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'loopback_ip_addr'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'neighbor_intf_ip_addr_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'atm_encapsulation'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'neighbor_intf_ip_addr'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'loopback_ip_addr_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vlan_id_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vlan_user_priority'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'intf_ip_addr'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'mac_address_init'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vlan_id_mode'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vlan_id'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vpi_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vpi'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'intf_prefix_length'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci'}
    
    #global connect_output apiData
    #set intfArgs {}
    #set unconnectedIntfArgs {}
    #if {[lsearch $args -reset ] != -1} {
    #     set args [lremove  $args -reset]
    #}
    #
    #set args2 $args
    #Convert_List_To_Keyedlist $args2

    #if {[lsearch $args "-mac_address_init"] != -1} {
    #    set srcmac [keylget apiData(expArgs) -mac_address_init]
    #    lappend intfArgs -src_mac_addr $srcmac   
    #    keyldel apiData(expArgs) -mac_address_init		
    #}

    #if {[lsearch $args "-intf_ip_addr"] != -1} {
    #    set mac [keylget apiData(expArgs) -intf_ip_addr]
    #    lappend intfArgs -intf_ip_addr $mac 
    #    lappend unconnectedIntfArgs -gateway $mac
    #    keyldel apiData(expArgs) -intf_ip_addr		
    #}
    #    
    #if {[lsearch $args "-neighbor_intf_ip_addr"] != -1} {
    #    set mac [keylget apiData(expArgs) -neighbor_intf_ip_addr]
    #    lappend intfArgs -gateway $mac
    #    keyldel apiData(expArgs) -neighbor_intf_ip_addr		
    #}

    #if {[lsearch $args "-port_handle"] != -1} {
    #    set ph [keylget apiData(expArgs) -port_handle]
    #    lappend intfArgs -port_handle $ph
    #    lappend unconnectedIntfArgs -port_handle $ph
    #}
    #    
    #if {[lsearch $args "-loopback_ip_addr"] != -1} {
    #    set loopbackAddr [keylget apiData(expArgs) -loopback_ip_addr]
    #    lappend unconnectedIntfArgs -intf_ip_addr $loopbackAddr
    #}

    #set args [Convert_Keyedlist_To_List $apiData(expArgs)]


    #if {[llength $intfArgs] >= 1} {

    #    if {[lsearch $intfArgs "-src_mac_addr"] != -1} {
    #        set api "interface_config -mode destroy -src_mac_addr $srcmac -port_handle $ph"
    #        puts "interface_config destroy is $api" 
    #        set ret [::ixia::executeInChild $api]
    #        puts "return is $ret"
    #
    #    }

    #    set api "interface_config $intfArgs -mode config"
    #    puts "interface_config is $api"
    #    set ret [::ixia::executeInChild $api]
    #    puts "return is $ret"
    #}

    #if {[lsearch $unconnectedIntfArgs "-intf_ip_addr"] != -1} {
    #    set api "interface_config $unconnectedIntfArgs -mode config -check_gateway_exists 1"
    #    puts "interface_config is $api"
    #    set ret [::ixia::executeInChild $api]
    #    puts "return is $ret"
    #}

    if {[lsearch $args -reset ] != -1} {
         set args [lremove  $args -reset]
         
    }

    global apiData
    set args1 $args
    Convert_List_To_Keyedlist $args1
    if {[lsearch $args "-mac_address_init"] != -1} {
        puts "removing -mac_address_init"
        set srcmac [keylget apiData(expArgs) -mac_address_init]
        set ph [keylget apiData(expArgs) -port_handle] 
        set api "interface_config -mode destroy -src_mac_addr $srcmac -port_handle $ph"
        set ret [::ixia::executeInChild $api]
    }
    set args [Convert_Keyedlist_To_List $apiData(expArgs)]

    set api "emulation_ospf_config $args -reset 1"

    puts "emulation ospf config is $api"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rip_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_rip_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::dhcp_server_extension_config {args} {
    set api "dhcp_server_extension_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_dhcp_group_config {args} {
    #Body { Arguments with no mandatory tag argument 'no_write'}
    set api "emulation_dhcp_group_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_bfd_session_config {args} {
    set api "emulation_bfd_session_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rsvp_info {args} {
    set api "emulation_rsvp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::convert_porthandle_to_vport {args} {
    set api "convert_porthandle_to_vport $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pim_group_config {args} {
    set api "emulation_pim_group_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_mplstp_config {args} {
    set api "emulation_mplstp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::connect {args} {
    puts "wrapper connect proc ::ixia::connect"
    global connect_output apiData
    puts "args: $args"
    if {[lsearch $args -reset ] != -1} {
         set args [lremove  $args -reset]
   }

    Convert_List_To_Keyedlist $args
    if {[lsearch $args "-ixnetwork_tcl_server"] != -1} {
        puts "Removing -ixnetwork_tcl_server"
        keyldel apiData(expArgs) -ixnetwork_tcl_server
    }
    if {[lsearch $args "-interactive"] != -1} {
        puts "Removing -interactive"
        keyldel apiData(expArgs) -interactive
    }
	if {[lsearch $args "-reset"] != -1} {
        puts "Removing -reset"
        keyldel apiData(expArgs) -reset
    }

    set args [Convert_Keyedlist_To_List $apiData(expArgs)]
    set api "connect $args -tcl_server $apiData(tcl_server) -reset 1"
    #puts "api : $api"
    set connect_output [::ixia::executeInChild $api]
    #puts "connect out: $connect_output"
    return $connect_output
    
}

proc ::ixia::emulation_mplstp_control {args} {
    set api "emulation_mplstp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_fport_vnport_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "fc_fport_vnport_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_lacp_link_config {args} {
    #Body { Arguments with no mandatory tag argument 'inter_marker_pdu_delay'}
    #Body { Arguments with no mandatory tag argument 'collecting_flag'}
    #Body { Arguments with no mandatory tag argument 'collector_max_delay'}
    #Body { Arguments with no mandatory tag argument 'actor_system_id'}
    #Body { Arguments with no mandatory tag argument 'actor_port_num_step'}
    #Body { Arguments with no mandatory tag argument 'actor_port_pri_step'}
    #Body { Arguments with no mandatory tag argument 'actor_system_pri'}
    #Body { Arguments with no mandatory tag argument 'lacp_activity'}
    #Body { Arguments with no mandatory tag argument 'support_responding_to_marker'}
    #Body { Arguments with no mandatory tag argument 'port_handle'}
    #Body { Arguments with no mandatory tag argument 'lag_count'}
    #Body { Arguments with no mandatory tag argument 'actor_key_step'}
    #Body { Arguments with no mandatory tag argument 'marker_req_mode'}
    #Body { Arguments with no mandatory tag argument 'port_mac_step'}
    #Body { Arguments with no mandatory tag argument 'actor_port_num'}
    #Body { Arguments with no mandatory tag argument 'marker_res_wait_time'}
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'actor_system_pri_step'}
    #Body { Arguments with no mandatory tag argument 'distributing_flag'}
    #Body { Arguments with no mandatory tag argument 'auto_pick_port_mac'}
    #Body { Arguments with no mandatory tag argument 'actor_key'}
    #Body { Arguments with no mandatory tag argument 'send_marker_req_on_lag_change'}
    #Body { Arguments with no mandatory tag argument 'lacpdu_periodic_time_interval'}
    #Body { Arguments with no mandatory tag argument 'port_mac'}
    #Body { Arguments with no mandatory tag argument 'actor_port_pri'}
    #Body { Arguments with no mandatory tag argument 'reset'}
    #Body { Arguments with no mandatory tag argument 'actor_system_id_step'}
    #Body { Arguments with no mandatory tag argument 'sync_flag'}
    #Body { Arguments with no mandatory tag argument 'no_write'}
    #Body { Arguments with no mandatory tag argument 'send_periodic_marker_req'}
    #Body { Arguments with no mandatory tag argument 'lacp_timeout'}
    #Body { Arguments with no mandatory tag argument 'aggregation_flag'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_lacp_link_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ldp_info {args} {
    set api "emulation_ldp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rsvp_config {args} {
    set api "emulation_rsvp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ancp_config {args} {
    set api "emulation_ancp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::convert_portname_to_vport {args} {
    set api "convert_portname_to_vport $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_elmi_control {args} {
    set api "emulation_elmi_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_efm_org_var_config {args} {
    set api "emulation_efm_org_var_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_fport_stats {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "fc_fport_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ldp_control {args} {
    set api "emulation_ldp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_bgp_info {args} {
    set api "emulation_bgp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_twamp_control {args} {
    set api "emulation_twamp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::packet_config_buffers {args} {
    if {[lsearch $args -data_plane_capture_enable ] != -1} {
         set args [lremove  $args -data_plane_capture_enable]

    }
    set api "packet_config_buffers $args -data_plane_capture_enable 1"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ldp_route_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'no_write'}
    set api "emulation_ldp_route_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::session_info {args} {
    set api "session_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_efm_control {args} {
    set api "emulation_efm_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::find_in_csv {args} {
    set api "find_in_csv $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::l2tp_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'action'
    if {[lsearch $args "-action"] == -1} {
        error "Missing Mandatory Argument \"action\""
    }
    set api "l2tp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_mld_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'no_write'}
    global connect_output apiData
    set args2 $args
    Convert_List_To_Keyedlist $args2

    if {[lsearch $args "-port_handle"] != -1} {
        set ph [keylget apiData(expArgs) -port_handle]
    }
	
    if {[lsearch $args "-mac_address_init"] != -1} {
        set srcmac [keylget apiData(expArgs) -mac_address_init]
        set api "interface_config -mode destroy -src_mac_addr $srcmac -port_handle $ph"
        puts "interface_config destroy is $api"
	set ret [::ixia::executeInChild $api]
        puts "return is $ret"
    }
    set api "emulation_mld_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_dhcp_server_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'action'
    if {[lsearch $args "-action"] == -1} {
        error "Missing Mandatory Argument \"action\""
    }
    set api "emulation_dhcp_server_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::pppox_stats {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'handle'
    if {[lsearch $args "-handle"] == -1} {
        error "Missing Mandatory Argument \"handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "pppox_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::dhcp_extension_stats {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "dhcp_extension_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_oam_info {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_oam_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::packet_config_filter {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gfp_bad_fcs_error'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pattern_atm'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gfp_payload_crc'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pattern_offset_atm'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vci_count'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vpi_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vpi'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pattern_mask_atm'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gfp_tHec_error'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gfp_error_condition'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'no_write'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'vpi_count'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gfp_eHec_error'}
    set api "packet_config_filter $args " 
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pbb_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_pbb_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_stp_info {args} {
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_stp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_client_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "fc_client_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ospf_info {args} {
    #Body { Arguments with no mandatory tag argument 'port_handle'}
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_ospf_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::capture_packets {args} {
    set api "capture_packets $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_twamp_info {args} {
    set api "emulation_twamp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_cfm_mip_mep_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_cfm_mip_mep_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pbb_custom_tlv_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'bridge_handle'
    if {[lsearch $args "-bridge_handle"] == -1} {
        error "Missing Mandatory Argument \"bridge_handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_pbb_custom_tlv_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pim_info {args} { }
proc ::ixia::emulation_pbb_trunk_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'bridge_handle'
    if {[lsearch $args "-bridge_handle"] == -1} {
        error "Missing Mandatory Argument \"bridge_handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_pbb_trunk_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::traffic_control {args} {
    #set res [::ixia::test_control -action stop_all_protocols]
    #sleep 20
    #set res [::ixia::test_control -action start_all_protocols]
    #global apiData
    #set args2 $args
    #Convert_List_To_Keyedlist $args2
    #set args1 $args
    #if {[lsearch $args1 "run"] != -1} {
        #set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action stop"
        #puts $api
        #set traffic [::ixia::executeInChild $api] 
        #set api "reset_port -mode reboot_port_cpu -protocol all -port_handle [keylget apiData(expArgs) -port_handle]"
        #puts $api
        #set traffic [::ixia::executeInChild $api] 
        #set api "test_control -action start_all_protocols"
        #puts $api
        #set traffic [::ixia::executeInChild $api]
        #set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action regenerate"
        #puts $api
        #set traffic [::ixia::executeInChild $api]
        #sleep 10
        #set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action apply"
        #puts $api
        #set traffic [::ixia::executeInChild $api]
        #sleep 10
   #}
   # if {[lsearch $args1 "sync_run"] != -1} {
   #     set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action stop"
   #     puts $api
   #     set traffic [::ixia::executeInChild $api]
        #set api "reset_port -mode reboot_port_cpu -protocol all -port_handle [keylget apiData(expArgs) -port_handle]"
        #puts $api
        #set traffic [::ixia::executeInChild $api]
        #set api "test_control -action start_all_protocols"
        #puts $api
        #set traffic [::ixia::executeInChild $api]
   #}
        #set api "traffic_control $args"
        #sleep 60
        #puts $api
        #set traffic [::ixia::executeInChild $api]
        #return $traffic
	set res [::ixia::test_control -action start_all_protocols]
	sleep 10
	global apiData
	set args2 $args
        Convert_List_To_Keyedlist $args2
	set args1 $args
        if {[lsearch $args1 "run"] != -1} {
	    set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action stop"
	    puts $api
	    set traffic [::ixia::executeInChild $api] 
            sleep 10
	    set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action regenerate"
	    puts $api
	    set traffic [::ixia::executeInChild $api]
	    sleep 10 
	    set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action apply"
	    puts $api 
	    set traffic [::ixia::executeInChild $api]
            sleep 10
	}
        set api "traffic_control $args"
	puts $api
        set res [::ixia::executeInChild $api]
        return $res
}
proc ::ixia::emulation_cfm_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_cfm_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rip_control {args} {
    set api "emulation_rip_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pim_control {args} {
    set api "emulation_pim_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_elmi_info {args} {
    set api "emulation_elmi_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_bfd_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "emulation_bfd_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::reboot_port_cpu {args} {
    set api "reboot_port_cpu $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_twamp_server_range_config {args} {
    set api "emulation_twamp_server_range_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::convert_vport_to_porthandle {args} {
    set api "convert_vport_to_porthandle $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_client_stats {args} {
    set api "fc_client_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pim_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_ip_addr'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'loopback_ip_address'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_dst_ip_addr'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_key_in_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_ip_addr_cstep'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'loopback_ip_address_cstep'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_count'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_ip_addr_lstep'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'loopback_count'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'loopback_ip_address_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_enable'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_dst_ip_addr_lstep'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_key_out_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_ip_prefix_length'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_unique'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_dst_ip_addr_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_src_ip_addr_mode'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_ip_addr_step'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_dst_ip_addr_cstep'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'gre_seq_enable'}
    set api "emulation_pim_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::packet_stats {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'framesize'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'enable_framesize'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'enable_pattern'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pattern_offset'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'chunk_size'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'enable_ethernet_type'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'ethernet_type'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'filename'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'pattern'}
    set api "packet_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_fport_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "fc_fport_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_isis_info {args} {
    set api "emulation_isis_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::get_port_list_from_connect {args} {
    set api "get_port_list_from_connect $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ldp_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'interface_mode'}
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'no_write'}
    set api "emulation_ldp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_dhcp_server_stats {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'action'
    if {[lsearch $args "-action"] == -1} {
        error "Missing Mandatory Argument \"action\""
    }
    set api "emulation_dhcp_server_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_cfm_vlan_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_cfm_vlan_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_cfm_info {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_cfm_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'action'
    if {[lsearch $args "-action"] == -1} {
        error "Missing Mandatory Argument \"action\""
    }
    set api "fc_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_mplstp_info {args} {
    set api "emulation_mplstp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_dhcp_server_config {args} {
    set api "emulation_dhcp_server_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_bfd_info {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "emulation_bfd_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::get_packet_content {args} {
    set api "get_packet_content $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::uds_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "uds_config $args"
    return [::ixia::executeInChild $api]
}

proc lremove {l p} {
    set a [lsearch -all -inline -not -exact $l $p]
    return $a
}

proc get_port_handle_info {ipAddress} {
     #package require IxTclNetwork
    set vports [interp eval $::ixia::TclInterp " ixNet getList [ixNet getRoot] vport "]
    
    set handle_list ""

    foreach vport_handle $vports {
        set interfaces [interp eval $::ixia::TclInterp " ixNet getList $vport_handle interface"]
        if {![string match $interfaces ""]} {
            foreach intf $interfaces {
                set ipv4Objs [interp eval $::ixia::TclInterp "ixNet getL $intf ipv4"]
                if {![string match $ipv4Objs ""]} {
                    set getIp [interp eval $::ixia::TclInterp " ixNet getA $intf/ipv4 -ip "]
                    if {[string match $getIp $ipAddress]} {
                        set vportObj [interp eval $::ixia::TclInterp " ixNet getA $vport_handle -connectedTo "]
                        puts "vportobj : $vportObj"
                        if {$vportObj ne ""} {
                            regexp -nocase {card:(\d+)\/port:(\d+)} $vportObj match card port
                            lappend handle_list "1/$card/$port"
                        }                    
                    }
                }
                set ipv6Objs [interp eval $::ixia::TclInterp "ixNet getL $intf ipv6"]
                if {![string match $ipv6Objs ""]} {
                    set val [catch {interp eval $::ixia::TclInterp " ixNet getA $intf/ipv6:1 -ip " } getIp]
                    if {![regexp -nocase {is null} $getIp match]} { 
                        if {[string match $getIp [expand_ipv6 $ipAddress]]} {
                            set vportObj [interp eval $::ixia::TclInterp " ixNet getA $vport_handle -connectedTo "]
                            puts "vportobj : $vportObj"
                            if {$vportObj ne ""} {
                                regexp -nocase {card:(\d+)\/port:(\d+)} $vportObj match card port
                                lappend handle_list "1/$card/$port"
                            } 
                        }
                    }
                }
                
            }
        }
    }
    puts "handle_list is : $handle_list"
    return $handle_list
}

proc findDstMacForTrafficItem {port} {
    
    lassign [split $port "/"] sequenceId card port
    set vports [interp eval $::ixia::TclInterp "ixNet getList [ixNet getRoot] vport"]
    foreach vportHdl $vports {
        set vportObj [interp eval $::ixia::TclInterp " ixNet getA $vportHdl -connectedTo "]
        if {[regexp -nocase ".*card:$card\/port:$port" $vportObj match]} {
            return [interp eval $::ixia::TclInterp "ixNet getA $vportHdl/discoveredNeighbor:1 -neighborMac"]
        }
    }            
}

proc ::ixia::traffic_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'command_response'}
    global connect_output apiData
    global env stream_name
    if {[info exists env(findNdr)]} {
	set findndr $env(findNdr)
    } else {
	    set findndr ""
    }
    set dstMac ""
    set srcMac ""
    set circuitType ""
    set args2 $args
    Convert_List_To_Keyedlist $args2
    if {[lsearch $args "-port_handle"] != -1} { 
	set api "traffic_control -port_handle [keylget apiData(expArgs) -port_handle] -action stop"
	puts $api
	set traffic [::ixia::executeInChild $api] 
    }
    sleep 20
    if {[lsearch $args "-vlan_id"] != -1} { 
       if {[lsearch $args "-vlan"] == -1} {
           lappend args -vlan enable
       }
    }
    if {[lsearch $args "-mac_dst"] != -1} {
       set mac [keylget apiData(expArgs) -mac_dst]
       set dstMac [format_mac_address $mac]
        
    }   
 
    if {[lsearch $args "-circuit_endpoint_type"] != -1} {
       set circuitType [keylget apiData(expArgs) -circuit_endpoint_type]
    }
    puts "circuit type is $circuitType"

    if {[lsearch $args "-port_handle2"] == -1} {
        #getting port_handle2 info here
        if {[lsearch $args "-ip_dst_addr"] != -1 || [lsearch $args "-ipv6_dst_addr"] != -1} {
            if {[lsearch $args "-ip_dst_addr"] != -1} {
                set ip [keylget apiData(expArgs) -ip_dst_addr]
                set port_handle2 [get_port_handle_info $ip]
                if { [ regexp  {([0-9]+).([0-9]+).([0-9]+).([0-9]+)} $ip dump oct1 oct2 oct3 oct4] } {
                     if { $oct1 > 224 } {
                          set temp_mac [mcastIPToMac $ip]
                          if {[lsearch $args "-mac_dst"] == -1} {
                              set dstMac_multicast [format_mac_address $temp_mac]
                              lappend args -mac_dst $dstMac_multicast
                          }

                     }
                }

        } elseif {[lsearch $args "-ipv6_dst_addr"] != -1} {
            set ip [keylget apiData(expArgs) -ipv6_dst_addr]
                set port_handle2 [get_port_handle_info $ip]
				set ip [get_ipv6_full_add $ip]
				if { [ regexp  {([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+)} \
				$ip dump oct1 oct2 oct3 oct4 oct5 oct6 oct7 oct8] } {
				if { [expr 0x$oct1] > 65281 || [expr 0x$oct1] < 65535 } {
					set temp_mac [mcastIPv6ToMac $ip]
				if {[lsearch $args "-mac_dst"] == -1} {
                              	set dstMac_multicast [format_mac_address $temp_mac]
                              	lappend args -mac_dst $dstMac_multicast
                          }
		}
	}
				
        } 
           if {![string match $port_handle2 ""]} {
                lappend args -port_handle2 $port_handle2
                lappend args -convert_to_raw 1 -track_by traffic_item
		if {[lsearch $args "-mac_dst"] == -1} {
                   set macDst ""
                   foreach vport [keylget apiData(expArgs) -port_handle]     {
		        lappend macDst [findDstMacForTrafficItem $vport]
		   }
		   if {$macDst ne ""} {
			lappend args -mac_dst $macDst
		   }
		}
            } elseif {[string match $port_handle2 ""] && [lsearch $args "-mac_dst"] == -1  } {
                set macDst ""
                foreach vport [keylget apiData(expArgs) -port_handle]     {
                    lappend macDst [findDstMacForTrafficItem $vport]
                }
                if {$macDst ne ""} {
                    lappend args -mac_dst $macDst
                }
                set port_list [keylget connect_output vport_list]
                puts "port_list: $port_list"
                set port_list_length [llength [keylget connect_output vport_list]]

                if {$port_list_length == 1} {
                    lappend args -circuit_type quick_flows
                } elseif {$port_list_length >= 2} {
                    foreach vport [keylget apiData(expArgs) -port_handle]  {
                        regsub -all $vport $port_list {} port_list
                    }
                    #set port_handle2 [lindex $port_list {}]
                    regsub -all "{" $port_list {} port_handle2
                    regsub -all "}" $port_handle2 {} port_handle2
                    puts "port_handle2 in mac_dst not there : $port_handle2"

                    lappend args -port_handle2 $port_handle2 -track_by traffic_item
                }
           
            } elseif {[string match $port_handle2 ""] && [lsearch $args "-mac_dst"] != -1  } {
                set port_list [keylget connect_output vport_list]
                puts "port_list: $port_list"
                set port_list_length [llength [keylget connect_output vport_list]]

                if {$port_list_length == 1} {
                    lappend args -circuit_type quick_flows
                } elseif {$port_list_length >= 2} {
                    foreach vport [keylget apiData(expArgs) -port_handle]  {
                        regsub -all $vport $port_list {} port_list
                    }
                    #set port_handle2 [lindex $port_list {}]
                    regsub -all "{" $port_list {} port_handle2
                    regsub -all "}" $port_handle2 {} port_handle2
                    puts "port_handle2 in mac_dst not there : $port_handle2"

                    lappend args -port_handle2 $port_handle2 -track_by traffic_item
                }

                        } else {
                if {[lsearch $args "-ip_src_addr"] != -1} {
                    set ip [keylget apiData(expArgs) -ip_src_addr]
                    puts "Source ip is $ip"
                    set handle [get_emulation_handle $ip]
                    lappend args -emulation_src_handle $handle
                    lappend args -circuit_endpoint_type ipv4 -track_by traffic_item
                    
                }
                
                if {[lsearch $args "-ip_dst_addr"] != -1} {
                    set ip [keylget apiData(expArgs) -ip_dst_addr]
                    puts "Dest ip is $ip"
                    set handle [get_emulation_handle $ip]
                    lappend args -emulation_dst_handle $handle
                }
                #lappend args -circuit_endpoint_type ipv4 -track_by traffic_item
            
                if {[lsearch $args "-ipv6_src_addr"] != -1} {
                    set ip [keylget apiData(expArgs) -ipv6_src_addr]
                    #puts "source ipv6 is $ip"
                    set handle [get_emulation_handle_ipv6 $ip]
                    lappend args -emulation_src_handle $handle
                    lappend args -circuit_endpoint_type ipv6 -track_by traffic_item
                }
                if {[lsearch $args "-ipv6_dst_addr"] != -1} {
                    set ip [keylget apiData(expArgs) -ipv6_dst_addr]
                    #puts "destination ipv6 is $ip"
                    set handle [get_emulation_handle_ipv6 $ip]
                    lappend args -emulation_dst_handle $handle
                }
     
            }
        }
    } else {

        if {[lsearch $args "-ip_dst_addr"] != -1 || [lsearch $args "-ipv6_dst_addr"] != -1} {
            if {[lsearch $args "-ip_dst_addr"] != -1} {
                set ip [keylget apiData(expArgs) -ip_dst_addr]
                set port_handle2 [get_port_handle_info $ip]
                if { [ regexp  {([0-9]+).([0-9]+).([0-9]+).([0-9]+)} $ip dump oct1 oct2 oct3 oct4] } {
                     if { $oct1 > 224 } {
                          set temp_mac [mcastIPToMac $ip]
                          if {[lsearch $args "-mac_dst"] == -1} {
                              set dstMac_multicast [format_mac_address $temp_mac]
                              lappend args -mac_dst $dstMac_multicast
                          }

                     }
                }

           } elseif {[lsearch $args "-ipv6_dst_addr"] != -1} {
                set ip [keylget apiData(expArgs) -ipv6_dst_addr]
                set port_handle2 [get_port_handle_info $ip]
                set ip [get_ipv6_full_add $ip]
                if { [ regexp  {([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+):([A-Z0-9]+)} \
                     $ip dump oct1 oct2 oct3 oct4 oct5 oct6 oct7 oct8] } {
                     if { [expr 0x$oct1] > 65281 || [expr 0x$oct1] < 65535 } {
                          set temp_mac [mcastIPv6ToMac $ip]
                          if {[lsearch $args "-mac_dst"] == -1} {
                                set dstMac_multicast [format_mac_address $temp_mac]
                                lappend args -mac_dst $dstMac_multicast
                          }
                     }
                }

           }
       }
    }
 
    set new_args {}  
    foreach i $args {
        if {[regexp {^-\w+$} $i]} {
            lappend new_args $i
        } 
    }
    
    foreach i $new_args {
        if {$i == "-no_write"} {
            set args [lreplace $args [lsearch $args $i] [lsearch $args $i]+1]
        } 
    }
    
    if {[lsearch $args "-l3_protocol"] != -1} {
        set ip_protocol [keylget apiData(expArgs) -l3_protocol]
        if {[lsearch $args "-circuit_endpoint_type"] == -1} {
            if {[string match $ip_protocol "arp"]} {
                lappend args -circuit_endpoint_type ipv4_arp
            } else {
                lappend args -circuit_endpoint_type $ip_protocol
            }
        }
    }

    regsub -all "{" $args {} args
    regsub -all "}" $args {} args

    puts "args now : $args"

    Convert_List_To_Keyedlist $args
    
    if {[lsearch $args "-mac_dst_mode"] != -1} {
           keyldel apiData(expArgs) -mac_dst_mode
    }

    if {[lsearch $args "-mac_src_mode"] != -1} {
           keyldel apiData(expArgs) -mac_src_mode
    }
	
	if {[lsearch $args "-signature"] != -1} {
           keyldel apiData(expArgs) -signature
    }
	if {[lsearch $args "-signature_offset"] != -1} {
           keyldel apiData(expArgs) -signature_offset
    }
    if {[lsearch $args "-integrity_signature"] != -1} {
           keyldel apiData(expArgs) -integrity_signature
    }
    if {[lsearch $args "-integrity_signature_offset"] != -1} {
           keyldel apiData(expArgs) -integrity_signature_offset
    }
    if {[lsearch $args "-pgid_mode"] != -1} {
			
	set pgid_mode [keylget apiData(expArgs) -pgid_mode]
	if {[string match $pgid_mode "custom"]} {
		keyldel apiData(expArgs) -pgid_mode
        }
    }
	if {[lsearch $args "-pgid_offset"] != -1} {
			
		    set pgid_offset [keylget apiData(expArgs) -pgid_offset]
		    keyldel apiData(expArgs) -pgid_offset
       }
        
    if {[lsearch $args "-pgid_value"] != -1} {
        puts "Removing -pgid value"
        keyldel apiData(expArgs) -pgid_value
    }

    if {[lsearch $args "-ethernet_type"] != -1} {
        puts "Removing -ethernet_type value"
        keyldel apiData(expArgs) -ethernet_type
    }

    if {[lsearch $args "-enable_pgid"] != -1} {
        puts "Removing -enable_pgid"
        keyldel apiData(expArgs) -enable_pgid
    }
    if {![string match $dstMac ""]}  {
        puts "removing -mac_dst"
        keyldel apiData(expArgs) -mac_dst 
    }
    set args [Convert_Keyedlist_To_List $apiData(expArgs)]
    if {![string match $dstMac ""]}  {
        puts "adding -mac_dst"
        lappend args -mac_dst $dstMac
    }
    if {![string match $circuitType ""]} {
        if {[string match $circuitType "arp"]} {
            puts "adding -circuit_endpoint_type ipv4_arp"
            lappend args -circuit_endpoint_type ipv4_arp
        } else {
            lappend args -circuit_endpoint_type $circuitType
        }
    }
    if {[lsearch $args "-track_by"] == -1} {
       lappend args -track_by traffic_item
    }
    if {[lsearch $args "-name"] != -1} {
	 set fragname [keylget apiData(expArgs) -name]
         if {[string equal "FragStream1" $fragname]} {
	     lappend args -ip_fragment_last 0
	 }
         if {[string equal "FragStream2" $fragname]} {
	     lappend args -ip_fragment_offset 34
	 }
    }

    if {[string match $findndr "ndr"]} {
	set mod [keylget apiData(expArgs) -mode]
	if {[string equal "modify" $mod]} {
            set stream [keylget apiData(expArgs) -stream_id]
	    set traffic [interp eval $::ixia::TclInterp " ixNet getList [ixNet getRoot] traffic "]
	    set trafficItemList [interp eval $::ixia::TclInterp " ixNet getL $traffic trafficItem "]
	    foreach trafficItem $trafficItemList {
		set result [regexp {::ixNet::OBJ-/traffic/trafficItem:(\d+)} $trafficItem match streamId]
		if {[string equal $stream $streamId]} {
		    set streamName [interp eval $::ixia::TclInterp " ixNet getA $trafficItem -name "]
		}
	    }
	    keylset apiData(expArgs) -stream_id $streamName
        }
        set args [Convert_Keyedlist_To_List $apiData(expArgs)]
	if {[lsearch $args "-track_by"] == -1} {
		lappend args -track_by traffic_item
	}
	set api "traffic_config $args "
	set trafficConfig [::ixia::executeInChild $api]
	set mod [keylget apiData(expArgs) -mode]
	if {[string equal "create" $mod]} {
	    keylset trafficConfig stream_id $stream_name
            set stream_name [expr {$stream_name + 1}]
	}
	return $trafficConfig
    } else {
	set api "traffic_config $args"
        return [::ixia::executeInChild $api]
    }
}

proc format_mac_address { macAddr } {

    puts "mac is : $macAddr "

    regsub -all {[.: ]} $macAddr  "" macAddr

    regexp -nocase {([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{2})([[:xdigit:]]{2})} $macAddr dummy mac1 mac2 mac3 mac4 mac5 mac6
    set macAddr $mac1:$mac2:$mac3:$mac4:$mac5:$mac6


    #if {[string length $macAddr]==12} {
    #  for {set i 0; set j 1} {$i < 11} {incr i 2; incr j 2} {
    #      lappend tmp [string range $macAddr $i $j]
    #  }
    #  set macAddr $tmp
    #}
 
    return $macAddr
        
}

proc Convert_List_To_Keyedlist {lst} {
    global apiData
    set apiData(expArgs) ""

    #set expressionList [split $lst "-"]
    set newElem [string map {" -" \0} [join [list " " $lst]]]
    set expressionList [split $newElem \0]

    foreach value $expressionList {
        if { [llength $value] >= 2} {
	    #regsub -all  [lindex $value 0]  $value "" val
	    keylset apiData(expArgs) -[lindex $value 0] [lreplace $value 0 0]  
	} elseif {[llength $value] == 1} {
	    keylset apiData(expArgs) -[lindex $value 0] 1
	}
    }

    #foreach key [keylkeys keyList] {
    #    lappend expListArgs $key [keylget keyList $key]
    #}

    #foreach {key val} $lst {
    #    keylset apiData(expArgs) $key $val
    #}
}

proc Convert_Keyedlist_To_List {keyList} {
    global apiData
    set expListArgs ""

    foreach key [keylkeys keyList] {
        lappend expListArgs $key [keylget keyList $key]
    }
    return $expListArgs
}

proc ::ixia::emulation_oam_config_topology {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_oam_config_topology $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::test_control {args} {
    set api "test_control $args"
    return [::ixia::executeInChild $api]
}
proc ::ixia::test_stats {args} {
    set api "test_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::l2tp_stats {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'handle'
    if {[lsearch $args "-handle"] == -1} {
        error "Missing Mandatory Argument \"handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "l2tp_stats $args"
    return [::ixia::executeInChild $api]
}
proc ::ixia::increment_ipv6_address {args} {
    set ipAddress $args
    if {[regexp -nocase {^([a-fA-F0-9]+):([a-fA-F0-9]+):([a-fA-F0-9]+)::([a-fA-F0-9]+)$} $ipAddress match  m1 m2 m3 m4]} {
         set m5 [expr $m4+1]
         set ipAddress $m1:$m2:$m3:0:0:0:0:$m5
    }
    return $ipAddress
}

proc ::ixia::emulation_bgp_route_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'no_write'}
    set api "emulation_bgp_route_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::packet_config_triggers {args} {
    puts "inside wrapper ::ixia::packet_config_triggers"
    global apiData
    set args1 $args
    Convert_List_To_Keyedlist $args1
    if {[lsearch $args "-port_handle"] != -1} {
        set ph [keylget apiData(expArgs) -port_handle]
        puts $ph 
        set res [ixia::packet_config_buffers -port_handle $ph ]
    }
    set api "packet_config_triggers $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_isis_topology_route_config {args} {
    set api "emulation_isis_topology_route_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_dhcp_stats {args} {
    set api "emulation_dhcp_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_twamp_control_range_config {args} {
    set api "emulation_twamp_control_range_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::device_info {args} {
    set api "device_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_cfm_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "emulation_cfm_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_eigrp_route_config {args} {
    set api "emulation_eigrp_route_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::reset_port {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'protocol'
    if {[lsearch $args "-protocol"] == -1} {
        error "Missing Mandatory Argument \"protocol\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "reset_port $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::dhcp_client_extension_config {args} {
    set api "dhcp_client_extension_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::l2tp_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'l2tp_dst_addr'
    if {[lsearch $args "-l2tp_dst_addr"] == -1} {
        error "Missing Mandatory Argument \"l2tp_dst_addr\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'num_tunnels'
    if {[lsearch $args "-num_tunnels"] == -1} {
        error "Missing Mandatory Argument \"num_tunnels\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'l2_encap'
    if {[lsearch $args "-l2_encap"] == -1} {
        error "Missing Mandatory Argument \"l2_encap\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'l2tp_src_addr'
    if {[lsearch $args "-l2tp_src_addr"] == -1} {
        error "Missing Mandatory Argument \"l2tp_src_addr\""
    }
    set api "l2tp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rip_route_config {args} {
    set api "emulation_rip_route_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_client_options_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "fc_client_options_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_lacp_info {args} {
    #Body { Arguments with no mandatory tag argument 'port_handle'}
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_lacp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_igmp_querier_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_igmp_querier_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ancp_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'action_control'
    if {[lsearch $args "-action_control"] == -1} {
        error "Missing Mandatory Argument \"action_control\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'action'
    if {[lsearch $args "-action"] == -1} {
        error "Missing Mandatory Argument \"action\""
    }
    set api "emulation_ancp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::l3vpn_generate_stream {args} {
    set api "l3vpn_generate_stream $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_dhcp_config {args} {
    #Body { Arguments with no mandatory tag argument 'no_write'}
    set api "emulation_dhcp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_eigrp_info {args} {
    set api "emulation_eigrp_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::fc_fport_global_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "fc_fport_global_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_mplstp_lsp_pw_config {args} {
    set api "emulation_mplstp_lsp_pw_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_twamp_config {args} {
    set api "emulation_twamp_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ancp_subscriber_lines_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_ancp_subscriber_lines_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_mld_group_config {args} {
    #Body { Need to fill equivalent logic in classic for FT Non-mandatory argument 'no_write'}
    set api "emulation_mld_group_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_mld_control {args} {
    set api "emulation_mld_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_cfm_md_meg_config {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    set api "emulation_cfm_md_meg_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_rsvp_tunnel_info {args} {
    set api "emulation_rsvp_tunnel_info $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_isis_config {args} {
    set api "emulation_isis_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_stp_lan_config {args} {
    #Body { Arguments with no mandatory tag argument 'count'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    #Body { Arguments with no mandatory tag argument 'mac_address'}
    #Body { Arguments with no mandatory tag argument 'mac_incr_enable'}
    #Body { Arguments with no mandatory tag argument 'vlan_enable'}
    #Body { Arguments with no mandatory tag argument 'port_handle'}
    #Body { Arguments with no mandatory tag argument 'vlan_id'}
    set api "emulation_stp_lan_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_stp_vlan_config {args} {
    #Body { Arguments with no mandatory tag argument 'count'}
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'root_priority'}
    #Body { Arguments with no mandatory tag argument 'vlan_port_priority'}
    #Body { Arguments with no mandatory tag argument 'internal_root_path_cost'}
    #Body { Arguments with no mandatory tag argument 'vlan_port_priority_step'}
    #Body { Arguments with no mandatory tag argument 'root_mac_address'}
    #Body { Arguments with no mandatory tag argument 'bridge_handle'}
    #Body { Arguments with no mandatory tag argument 'root_mac_address_step'}
    #Body { Arguments with no mandatory tag argument 'vlan_id'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_stp_vlan_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_igmp_control {args} {
    set api "emulation_igmp_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_pbb_control {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'mode'
    if {[lsearch $args "-mode"] == -1} {
        error "Missing Mandatory Argument \"mode\""
    }
    #Argument not supported in FT.This argument is Mandatory in Classic 'port_handle'
    if {[lsearch $args "-port_handle"] == -1} {
        error "Missing Mandatory Argument \"port_handle\""
    }
    set api "emulation_pbb_control $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_ancp_stats {args} {
    #Argument not supported in FT.This argument is Mandatory in Classic 'reset'
    if {[lsearch $args "-reset"] == -1} {
        error "Missing Mandatory Argument \"reset\""
    }
    set api "emulation_ancp_stats $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_igmp_group_config {args} {
    set api "emulation_igmp_group_config $args"
    return [::ixia::executeInChild $api]
}

proc ::ixia::emulation_lacp_control {args} {
    #Body { Arguments with no mandatory tag argument 'port_handle'}
    #Body { Arguments with no mandatory tag argument 'handle'}
    #Body { Arguments with no mandatory tag argument 'mode'}
    set api "emulation_lacp_control $args"
    return [::ixia::executeInChild $api]
}


proc ::ixia::increment_ipv4_net {args} {
   set api "increment_ipv4_net $args"
   return [::ixia::executeInChild $api]
}



proc ixClearStats {ixPortList} {
   set status [::ixia::traffic_control  -action clear_stats]
}
proc mcastIPToMac { mcastIP } {

    set mcastMac 0000.0000.0000
    if { ![ regexp  {([0-9]+).([0-9]+).([0-9]+).([0-9]+)} $mcastIP dump oct1 oct2 oct3 oct4] } {
        puts "invalid ip format"
        return $mcastMac
    }
    if { $oct1 < 224 |  $oct1 > 239 } {
        puts "invlaid mcast IP"
        return $mcastMac
    }
    catch { unset mcastMac }
    set item {}
    set oct2 [expr $oct2 & 127]
    lappend item 5e [format "%02x" $oct2]
    regsub -all { } $item {} item2

    set item {}
    lappend item  [format "%02x" $oct3] [format "%02x" $oct4]
    regsub -all { } $item {} item3

    lappend mcastMac 0100 $item2 $item3
    regsub -all { } $mcastMac {.} mcastMac

    return $mcastMac
}

proc subnetmaskToCIDR { ip } {
    set sum 0
    if {[string length $ip]==2} {
        return $ip
    } else {
        foreach i [split $ip "."] {
            while { $i !=0} {
                set sum [expr $sum + [expr $i & 1]]
                set i [expr $i >> 1]
            }
        }
        return $sum
    }
}

