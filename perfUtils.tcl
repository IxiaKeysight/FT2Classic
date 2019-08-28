# $Id: perfUtils.tcl,v 1.9 2019/02/07 14:03:03 kkg Exp $
# Copyright (c) 2009,2014 by Cisco Systems, Inc.
#
# Name: perfUtils.tcl
#
# Purpose:
#   The perfUtils library currently has just one major proc
#   for finding NDR (No Drop Rate) and latency.
#   This is based on Binary Search algorithm.
#   This library can be used for other performance utilities as well.
#
# Author:
#   Muhammad A Imam - muimam@cisco.com
#   Yuefeng Jiang - yuefjian@cisco.com
#   Ruoying Pan - rupan@cisco.com
#
# Usage:
#   set auto_path [linsert $auto_path 0 \
#       [file join $env(AUTOTEST) regression lib mid_range_routing]]
#   package require perfUtils
#
# Description:
#   findNdr - The procedure uses a binary search algorithm to find the NDR
#             using the ports and streams information provided by the user.
#             The user must provide all of the mandatory argumrnts and
#             optionally can provide the optional arguments mentioned below.
#             The proc can also obtain latency based on statistical sampling.
#             The proc can handle any type of traffic that can be configured
#             in IxExplorer as streams. It handles multicast traffic seprately.
#             The proc assumes the following:
#             1. The traffic streams will be setup by the user
#             2. On receiving ports packets have to be filtered in UDS1 or UDS2
#   public proc:
#       perfUtils::findNdr
#       perfUtils::parseNdrResults
#       perfUtils::writePerfValues
#       perfUtils::writeMyPerfValues
#       perfUtils::generate_keyed_result
#   private proc:
#       perfUtils::_run_IxExplorer_test
#       perfUtils::_run_IxNetwork_test
#       perfUtils::_run_IxNetwork_test2
#       perfUtils::_get_txPkts_IxExplorer
#       perfUtils::_get_rxPkts_IxExplorer
#       perfUtils::_get_latency_IxExplorer
#       perfUtils::_run_traffic_IxExplorer
#       perfUtils::_set_curRate_IxNetwork
#       perfUtils::_enable_stats_IxNetwork
#       perfUtils::_get_txPkts_IxNetwork
#       perfUtils::_get_txPkts_IxNetwork2
#       perfUtils::_get_txRxPkts_IxNetwork
#       perfUtils::_get_rxPkts_IxNetwork
#       perfUtils::_get_rxPkts_IxNetwork2
#       perfUtils::_get_latency_IxNetwork
#       perfUtils::_get_latency_IxNetwork2
#       perfUtils::_run_traffic_IxNetwork
#       perfUtils::_maxrate
#       perfUtils::_maxrate2
#       perfUtils::_framesize
#       perfUtils::_parse_tx_ports
#       perfUtils::_parse_rx_ports
#       perfUtils::_parse_mtx_ports
#       perfUtils::_parse_mrx_ports
#       perfUtils::_error
#
# Requirements:
#   HLTAPI for generator being used
#
# Bugs:
#   Bugs need to fix
#        1.
#
# Limitations:
#        1. All ports involved in the test need to be of the same capacity
#           i.e. All of them to be 1Gig or 10Gig.
#           The API cannot handle if the situation
#           when one port is 1 Gig and the other is 10 Gig
#        2. The API assumes, if there are multiple streams per port,
#           all streams have the same frame size defined
#        3. If calculating NDR for IMIX, specify the max_rate, otherwise
#           the proc will puick a random max_rate based on the packet sizes
#package provide perfUtils 1.0
set script_dir [file dirname [info script]]
set sourcefile1 [file join $script_dir "mcpModules.tcl"]
set sourcefile2 [file join $script_dir "constants.h"]
if {[file exists $sourcefile1] && [file exists $sourcefile2]} {
    if { [catch {
        source [file join $script_dir "mcpModules.tcl"]
        source [file join $script_dir "constants.h"]
    } errmsg ] } {
        set diag "Couldn't source mcpModules.tcl or constants.h, err: $errmsg"
        ats_log -error $diag
        ats_results -result fail -goto end
    }
} else {
    set diag "Couldn't source mcpModules.tcl or constants.h, file not exist"
    ats_log -error $diag
    ats_results -result fail -goto end
}

namespace eval ::perfUtils {
    namespace export *
}

####################################################
# Description
####################################################
procDescr perfUtils::findNdr {

    Description:
        The procedure uses a binary search algorithm to find the NDR using the
        ports and streams information provided by the user. The user must
        provide all of the mandatory argumrnts and optionally can provide the
        optional arguments mentioned below. The proc can also obtain latency
        based on statistical sampling. The proc can handle any type of traffic
        that can be configured in IxExplorer as streams. The proc handles
        multicast traffic seprately.
        The proc assumes the following:
        1. The traffic streams will be setup by the user
        2. On receiving ports the packets have to be filtered in UDS1 or UDS2

    Usage:
        set result [perfUtils::findNdr                                  \
                -tx_ports       <Keyed List>                            \
                -rx_ports       <Keyed List>                            \
                -mtx_ports      <Keyed List>                            \
                -max_rate       <Numeric Value>                         \
                -min_rate       <Numeric Value>                         \
                -threshold      <Numeric Value>                         \
                -run_time       <Numeric value>                         \
                -uds            <uds1|uds2>                             \
                -debug          <0|1>                                   \
                -latency        <0|1>                                   \
                -uut            <Device Name as String>                 \
                -tr             <Other Device Name as String>           \
                -exec_cmds      <List of commands as Strings>           ]

    Example:
        keylset sendPorts port1.port 1/1/1
        keylset sendPorts port1.streams {1 2 3}
        keylset sendPorts port2.port 1/2/1
        keylset sendPorts port2.streams {4 5 6}

        keylset receivePorts port1.port 1/1/1
        keylset receivePorts port2.port 1/2/1

        set result [perfUtils::findNdr                                  \
                -tx_ports       $sendPorts                              \
                -rx_ports       $receivePorts                           \
                -max_rate       10000000                                \
                -min_rate       100000                                  \
                -threshold      100000                                  \
                -debug          1                                       \
                -run_time       100                                     \
                -latency        1                                       \
                -uut            $UUT                                    ]

    Arguments:
        -tx_ports       <Mandatory Argument> Keyed list in the following format
                        {port1 {{port 1/1/1} {streams {3 4 1}}}}
                        {port2 {{port 1/2/1} {streams {23 2 24 25}}}}
                        Example to define the keyed list:
                           keylset sendPorts port1.port 1/1/1
                           keylset sendPorts port1.streams {1 2 3}
                           keylset sendPorts port2.port 1/2/1
                           keylset sendPorts port2.streams {4 5 6}
                        Note: You have to give all the transmitting ports info
                              in a single keyed list as mentioned above in the
                              example. There is no limit on the number of
                              transmitting port that you may want to use as
                              long as all of them are of the same capacity.
                              e.g. all of them 10Gigs.
                              You MUST also include the multicast streams
                              in the tx stream list if you have mcast streams

        -rx_port        <Mandatory Argument> Keyed list in the following format
                        {port1 {{port 1/1/1}}} {port2 {{port 1/2/1}}}
                        Example to define the keyed list:
                            keylset receivePorts port1.port 1/1/1
                            keylset receivePorts port2.port 1/2/1
                        Note: You have to give all the receiving ports info
                              in a single keyed list as mentioned above in the
                              example. You can receive on any number of ports.

        -mtx_ports      <Optional Argument> Keyed list in the following format
                        {port2 {{port 1/2/1} {mcast_streams {5 6}}
                               {mcast_oifs {100 100}}}}
                        Example to define the keyed list:
                            keylset mcastPorts port2.port 1/2/1
                            keylset mcastPorts port2.mcast_streams {5 6}
                            keylset mcastPorts port2.mcast_oifs {100 100}
                        Note: You can have differnt replicas for differnt
                              streams. Therefore when you mention the multicast
                              streams you should also mention the number of
                              replicas you are expecting. If you have two
                              multicast streams defined you should also mention
                              the replicas (OIF) respectively. In the above
                              example stream 5 and 6 and multicast streams.
                              Each of them are supposed to replicate 100 times.

        -max_rate       <Optional Argument> This is the maximum rate the proc
                        is going to try on EACH PORT. So the rate you will
                        mention here will be per port rate in PPS. You should
                        account for packet size when mentioning the rate. The
                        procedure tries to find the NDR between the max_rate as
                        upper bound and min_rate as the lower bound. If you do
                        not define rate it will calculate the max rate based on
                        the port capacity and packet size used in the stream.

        -min_rate       <Optional Argument> This is the minimum rate in PPS
                        the proc is going to try, by default it is 1000

        -threshold      <Optional Argument> This is the thershold value in PPS.
                        The proc will not bother the differnce of this value
                        between the passing and failing NDR. By default is 1000

        -run_time       <Optional Argument> The proc runs the traffic for this
                        much amount of time. This is a vlue in seconds.
                        The default value is 120 seconds

        -uds            <Optional Argument> User can gather recieving traffic
                        stats on either UDS1 or UDS2. The user has to define
                        the right filters to cath the interesting traffic. By
                        default it looks for UDS1. If your traffic stats come
                        on UDS2 you can select uds2 and provide this argument

        -tx_mode        <Optional Argumnet> The API supports packet as well as
                        advanced streams. By default it is packet streams.
                        if your streams are advanced streams, use this optional
                        argument to define it is advanced. For advanced streams
                        the traffic rate will be devided over the number of
                        streams on each tx port

        -debug          <Optional Argument> by default the debug is OFF (0).
                        If you enable debug you can get additional log per port
                        to debug any issues. To enable set -debug value as 1

        -latency        <Optional Argument> By default the proc does not
                        calculate latency. If you enable latency by putting
                        -latency as 1 the proc will give you avg, min and max
                        latency. To obtain latency you should enable capture
                        filter and get a reasonable amount of packets in the
                        buffer (at least 2000)

        -min_cap_pkts   <Optional Arguments> By default the value is 20 packets
                        If this much amount of packet are not there capture
                        buffer the test is going to fail and will return error

        -uut            <Mandatory Argument> You must provide the UUT. On this
                        UUT you can run any commands at half of the run time
                        for stats or debug. The commands are supplied in the
                        -exec_cmds argument

        -tr             <Optional Argument> You can provide the TR. On this
                        RT you can run any commands at half of the run time
                        for stats or debug. The commands are supplied in the
                        -exec_cmds argument

        -tgen_app       <Optional Argument> By default its IxExplorer

        -exec_cmds      <Optional Argument> You can provide the list of
                        show commands to run at half run time. By default
                        it runs the follwoing three commands
       console $uut
       EnablePw [test_passwd enable]
       $uut exec "show platform hardware qfp active datapath utilization"
  $uut exec "show platform hardware qfp active infrastructure exmem statistics"
              $uut exec "show platform software status control-processor brief"
                  $uut exec "show platform hardware qfp active statistics drop"
                        You should supply as a list e.g.
                            -exec_cmds {"sh plat hard qfp active data util"\
                                        "sh plat hard qfp act infra exmem sta"\
                                        "sh plat soft st control-processor br"}

        -loss_rate      <Optional Argument> loss_rate% number of packets lost
                        can be acceptable and regard as Non-drop.By default
                        it's 0.0, indicating the receiving ports shouldn't
                        lose packets compared with the sending ports.

    Return Value:
        Returns a keyed list with structure as follows:

        status <1|0> - 1 for Pass 0 for Fail
        <<if passes>>
        ndr <NUMERIC> - in PPS
        numPkts <NUMERIC> - Number of packets captured on UDS4 for latency.
                If latency is not enabled  or there is no capture it is 0
        avgLatency <NUMERIC> - Averege latency in NanoSeconds
        minLatency <NUMERIC> - Minimum Latency in NanoSeconds
        maxLatency <NUMERIC> - Maximum Latency in NanoSeconds
        cmd_outputs <STRINGS> - Based onm the arguments provided
                output1
                output2
                ...
                ..
                .
        <<in case it fails>>
        log <STRING> - Message about failure
        tclErr <STRING> - The error thrown by TCL

} ; # End of procDescr

#######################################################
#This proc finds the NDR and returns NDR along with latencies and other stats
#######################################################
proc perfUtils::findNdr {args} {

    #mandatory args
    set man_args {
        -uut                    ANY
        -tx_ports               ANY
        -rx_ports               ANY
    }

    #optional_args
    set opt_args {
        -tr                     ANY
                                DEFAULT ""
        -mtx_ports              ANY
        -mrx_ports              ANY
        -forceTxPorts           NUMERIC
                                DEFAULT 0
        -latency                CHOICES 0 1
                                DEFAULT 0
        -latency_rates          NUMERIC
                                DEFAULT 95
        -latency_detail         CHOICES 0 1
                                DEFAULT 0
        -min_cap_pkts           NUMERIC
                                DEFAULT 20
        -run_time               NUMERIC
                                DEFAULT 120
        -max_rate               NUMERIC
                                DEFAULT 0
        -min_rate               NUMERIC
                                DEFAULT 1000
        -threshold              NUMERIC
                                DEFAULT 1000
        -frame_size             ANY
        -tx_mode                CHOICES packet advanced
                                DEFAULT packet
        -exec_cmds              ANY
                                DEFAULT {\
                      "show platform hardware qfp active datapath utilization"\
           "show platform hardware qfp active infrastructure exmem statistics"\
                       "show platform software status control-processor brief"\
                           "show platform hardware qfp active statistics drop"}
        -uds                    CHOICES uds1 uds2
                                DEFAULT uds1
        -tgen_app               CHOICES IxExplorer IxNetwork
                                DEFAULT IxNetwork
        -ixnetwork_root         ANY
        -ixnetwork_traffic      ANY
        -debug                  CHOICES 0 1
                                DEFAULT 0
        -loss_rate              ANY
                                DEFAULT 0.0
    }

    #Parse the dashed arguments
    parse_dashed_args -args $args \
                      -mandatory_args $man_args -optional_args $opt_args

    ats_log -info "FindNdr args:$args"

    #Define/initialize local variables
    set SUCCESS 1
    set FAILURE 0
    set returnList ""
    keylset returnList log ""
    keylset returnList tclErr ""
    append uds_count "$uds" "_count"
    append uds_count2 "$uds" "_frame_count"
    #debug 1
    #Parse keyed lists
    set txPorts ""; set txStreamSets ""; set txStreams ""; set numTxPorts 0
    if {[_parse_tx_ports txPorts txStreamSets txStreams numTxPorts returnList \
                         $tx_ports $debug] != $SUCCESS} {
        return $returnList
    }

    set rxPorts ""; set numRxPorts 0
    if {[_parse_rx_ports rxPorts numRxPorts returnList $rx_ports $debug] \
        != $SUCCESS} {
        return $returnList
    }

    set mtxPorts ""; set mtxStreamSets "";
    set mtxOifSets ""; set mtxStreams ""; set mtxOifs ""
    if {[info exists mtx_ports]} {
        if {[_parse_mtx_ports mtxPorts mtxStreamSets mtxOifSets mtxStreams \
                           mtxOifs returnList $mtx_ports $debug] != $SUCCESS} {
            return $returnList
        }
    } else {
        set mtx_ports ""
    }

    set mrxPorts ""; set numMrxPorts 1
    if {[info exists mrx_ports]} {
        if {[_parse_mrx_ports mrxPorts numMrxPorts returnList $mrx_ports \
                              $debug] != $SUCCESS} {
            return $returnList
        }
    } else {
        set mrx_ports ""
    }

    if {[info exists max_rate] && $max_rate < 1} {
        set maxRatePort [lindex $txPorts 0]
        set stream_id [lindex [lindex $txStreamSets 0] 0]
        #puts "_maxrate use: $stream_id"
        set max_rate [_maxrate2 $maxRatePort $stream_id]
    }

    if {[info exists frame_size]} {} else {
        set frame_size 0
        if {$tgen_app == "IxExplorer"} {
            set frameSizePort [lindex $txPorts 0]
            set stream_id [lindex [lindex $txStreamSets 0] 0]
            #puts "_framesize use: $stream_id"
            set frame_size [_framesize $frameSizePort $stream_id]
        }
    }

    #Initialize variables for results
    set numPkts 0
    set passNdr "NDR not found! Try using lower min_rate and threshold"
    set passNumPkts 0
    set passAvgLatency 0
    set passMinLatency 0
    set passMaxLatency 0
    set passCmdOutputs "No Passed Run! All iterations FAILED"
    set passCurRate 0
    set everPass 0
    #Initialize variables for while loop
    set org_min_rate $min_rate
    set nopass_threshold $min_rate
    if { $nopass_threshold > $threshold } {
        set nopass_threshold $threshold
    }
    set curRate $max_rate
    set iteration 1

    #start NDR binary search
    set latency1 0
    while {($max_rate - $threshold) >= $min_rate || \
     ( $org_min_rate == $min_rate && ($curRate - $nopass_threshold) > $org_min_rate) } {
# note: In original logic, if threshold is much larger than min_rate, and all former     
# iteration FAIL, then the condition in while-loop "($max_rate - $threshold) >= $min_rate" 
# will lead to break while and not try ~min_rate.
# e.g. min_rate=100, threshold=500, curRate=550 FAIL, set max_rate to 550, then     
# max_rate 550 - threshold 500 = 50 < min_rate 100, break while. So only try rate 550, 
# much bigger than the set min_rate value 100.
# So this mechanism to handle that if non of the iteration pass, go on try till near min_rate.
        set diag "Iteration: $iteration"
        ats_log -diag $diag

        #Switch on tgen_app
        switch $tgen_app {
            IxExplorer {
                #Run trafic @ curRate and get results - IxExplorer
                if {[_run_IxExplorer_test txPkts rxPkts numPkts avgLatency \
                minLatency maxLatency cmdOutputs returnList $txPorts $txStreams\
                $txStreamSets $tx_mode $rxPorts $mtxPorts $mtxStreams \
                $mtxStreamSets $mtxOifs $mtxOifSets $mtx_ports $run_time \
                $curRate $uds_count $min_cap_pkts $numRxPorts $numMrxPorts \
                $exec_cmds $uut $tr $latency1 0 $debug] != $SUCCESS} {
                    return $returnList
                }
            }

            IxNetwork {
                #Run trafic @ curRate and get results - IxNetwork
#                if {[_run_IxNetwork_test txPkts rxPkts avgLatency minLatency \
#                maxLatency ixNetworkStreamCount cmdOutputs $ixnetwork_root \
#                $curRate $run_time $exec_cmds $uut $latency1 $debug] \
#                != $SUCCESS} {
#                    return $returnList
#                }
                 #set numPkts $rxPkts
               if {[_run_IxNetwork_test2 txPkts rxPkts numPkts avgLatency \
               minLatency maxLatency cmdOutputs returnList $txPorts $txStreams\
               $txStreamSets $tx_mode $rxPorts $mtxPorts $mtxStreams \
               $mtxStreamSets $mtxOifs $mtxOifSets $mtx_ports $run_time \
               $curRate $uds_count2 $min_cap_pkts $numRxPorts $numMrxPorts \
               $exec_cmds $uut $tr $latency1 0 $debug] != $SUCCESS} {
                    return $returnList
               }
            }
        }

        #Checks for binary search
        #  $txPkts != $rxPkts
        set txPkts [expr {$txPkts*(100.0-$loss_rate)/100}]
        if {$debug == 1} {
            ats_log -info "loss rate:$loss_rate, txPkts:$txPkts"
        }
        if {$txPkts > $rxPkts || $rxPkts < $min_rate} {
            set result "\n\nFAILED line rate $curRate pps (per port),\
              loss_rate:$loss_rate"
            ats_log -result $result
            set max_rate $curRate
        } else {
            set result "\n\nPASSED line rate $curRate pps (per port),\
              loss_rate:$loss_rate"
            set everPass 1
            ats_log -result $result
            set min_rate $curRate
            #NDR if this is the final successful run
            if {$forceTxPorts > 0} {
                if {$tx_mode == "advanced"} {
                    set passNdr [expr {$curRate * $numTxPorts * $txStreams}]
                }
                set passNdr [expr {$curRate * $numTxPorts}]
            } else {
                if {$tx_mode == "advanced"} {
                #Added for IxNetwork
                    if {$tgen_app == "IxNetwork"} {
                        set passNdr [expr {$curRate * $numRxPorts}]
                      # set passNdr [expr {$curRate * $ixNetworkStreamCount}]
                      # set result "\nPassed line rate $curRate pps (per port),\
                     #  NDR:$passNdr,ixNetworkStreamCount:$ixNetworkStreamCount"
                    } else {
                        set passNdr [expr {$curRate * $numRxPorts}]
                    }
                } else {
                    set passNdr [expr {$curRate * $numRxPorts}]
                }
            }
            set passNumPkts $numPkts
            set passAvgLatency $avgLatency
            set passMinLatency $minLatency
            set passMaxLatency $maxLatency
            set passCmdOutputs $cmdOutputs
            set passCurRate $curRate
        }

        #Next traffic rate
        set curRate [mpexpr ($max_rate+$min_rate)/2]

        #Iteration counter
        set iteration [expr {$iteration + 1}]

    } ; # End of While

    # Find latencies at latency_rates
    if {$latency == 1} {
        foreach rate $latency_rates {
            set curRate [expr {($passCurRate*$rate)/100.00}]
            if {$latency_detail > 0} {set latency_detail $rate}
            switch $tgen_app {
                IxExplorer {
                    #Run trafic @ curRate and get results - IxExplorer
                    set diag "Post NDR iteration - @ $rate % \
                              - $curRate pps (per port)..."
                    ats_log -diag $diag
                    if {[_run_IxExplorer_test txPkts rxPkts numPkts avgLatency \
                    minLatency maxLatency cmdOutputs returnList $txPorts \
                    $txStreams $txStreamSets $tx_mode $rxPorts $mtxPorts \
                    $mtxStreams $mtxStreamSets $mtxOifs $mtxOifSets $mtx_ports \
                    $run_time $curRate $uds_count $min_cap_pkts $numRxPorts \
                    $numMrxPorts $exec_cmds $uut $tr $latency $latency_detail\
                    $debug] != $SUCCESS} {
                       return $returnList
                    }
                }
                IxNetwork {
                    #Run trafic @ curRate and get results - IxNetwork
                    set diag "Post NDR iteration - @ $rate % \
                              - $curRate pps (per port)..."
#                    ats_log -diag $diag
#                    if {[_run_IxNetwork_test txPkts rxPkts avgLatency \
#                    minLatency maxLatency ixNetworkStreamCount cmdOutputs \
#                    $ixnetwork_root $curRate $run_time $exec_cmds $uut \
#                    $latency $debug] != $SUCCESS} {
#                        return $returnList
#                    }
                     if {[_run_IxNetwork_test2 txPkts rxPkts numPkts avgLatency\
                     minLatency maxLatency cmdOutputs returnList $txPorts \
                     $txStreams $txStreamSets $tx_mode $rxPorts $mtxPorts \
                     $mtxStreams $mtxStreamSets $mtxOifs $mtxOifSets $mtx_ports \
                     $run_time $curRate $uds_count2 $min_cap_pkts $numRxPorts \
                     $numMrxPorts $exec_cmds $uut $tr $latency $latency_detail \
                     $debug] != $SUCCESS} {
                         return $returnList
                    }
                }
            }
            set numPkts $rxPkts
            keylset returnList latency($rate) $avgLatency
            keylset returnList latency(CUST) $avgLatency
        }
    }

    #Return keyed list
    keylset returnList status $everPass
    keylset returnList ndr $passNdr
    keylset returnList num_pkts $passNumPkts
    keylset returnList latency(NDR) $passAvgLatency
    keylset returnList min_latency $passMinLatency
    keylset returnList max_latency $passMaxLatency
    keylset returnList cmd_outputs $passCmdOutputs
    keylset returnList run_time $run_time
    keylset returnList frame_size $frame_size
    keylset returnList loss_rate $loss_rate

    return $returnList

} ; # End of Proc findNdr

######################################################################
##Procedure Header
# Name:
#    perfUtils::_run_IxExplorer_test
#
# Purpose:
#    run one iteration of IxExplorer.
#
# Synopsis:
#    _run_IxExplorer_test args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc runs IxExplorer test.
######################################################################
proc perfUtils::_run_IxExplorer_test {txPkts rxPkts numPkts avgLatency \
minLatency maxLatency cmdOutputs returnList txPorts txStreams txStreamSets \
tx_mode rxPorts mtxPorts mtxStreams mtxStreamSets mtxOifs mtxOifSets mtx_ports \
run_time curRate uds_count min_cap_pkts numRxPorts numMrxPorts exec_cmds uut \
tr latency latency_detail debug} {

    set SUCCESS 1
    upvar $txPkts txPktsLoc
    upvar $rxPkts rxPktsLoc
    upvar $numPkts numPktsLoc
    upvar $avgLatency avgLatencyLoc
    upvar $minLatency minLatencyLoc
    upvar $maxLatency maxLatencyLoc
    upvar $cmdOutputs cmdOutputsLoc
    upvar $returnList returnListLoc

    #Set Traffic Rate
    if {[_set_curRate_IxExplorer $txPorts $txStreamSets $tx_mode $mtxPorts \
        $mtxStreams $mtxOifs $mtx_ports $numMrxPorts $curRate] != $SUCCESS} {
        return $returnList
    }

    #Run Traffic
    set cmdOuputsLoc ""
    if {[_run_traffic_IxExplorer cmdOutputsLoc $txPorts $rxPorts $run_time \
                                 $exec_cmds $uut $tr] != $SUCCESS} {
        return $returnList
    }

    #Get Tx Stats
    set txPktsLoc [_get_txPkts_IxExplorer $txPorts $txStreamSets $mtxPorts \
                               $mtxStreamSets $mtxOifSets $mtx_ports $debug]

    #Get Rx Stats
    set rxPktsLoc [_get_rxPkts_IxExplorer $rxPorts $uds_count $debug]

    #Get Latency Stats
    set numPktsLoc 0;
    set avgLatencyLoc 0; set minLatencyLoc 0; set maxLatencyLoc 0
    if {$latency == 1} {
        if {[_get_latency_IxExplorer numPktsLoc avgLatencyLoc minLatencyLoc \
              maxLatencyLoc returnListLoc $rxPorts $min_cap_pkts $numRxPorts\
              $debug $latency_detail] != $SUCCESS} {
            return $returnList
        }
    }

    return 1
} ;  # End of Proc _run_IxExplorer_test

######################################################################
##Procedure Header
# Name:
#    perfUtils::_run_IxNetwork_test
#
# Purpose:
#    run one iteration of IxNetwork.
#
# Synopsis:
#    _run_IxNetwork_test args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc runs IxNetwork test.
######################################################################
proc perfUtils::_run_IxNetwork_test {txPkts rxPkts avgLatency minLatency \
maxLatency ixNetworkStreamCount cmdOutputs ixnetwork_root curRate run_time \
exec_cmds uut tr latency debug} {

    set SUCCESS 1
    upvar $txPkts txPktsLoc
    upvar $rxPkts rxPktsLoc
    upvar $avgLatency avgLatencyLoc
    upvar $minLatency minLatencyLoc
    upvar $maxLatency maxLatencyLoc
    upvar $ixNetworkStreamCount ixNetworkStreamCountLoc
    upvar $cmdOutputs cmdOutputsLoc

    #Set Traffic Rate
    if {[_set_curRate_IxNetwork $ixnetwork_root $curRate] != $SUCCESS} {
        return $returnList
    }

    #Enable Stats
    set txPkts [_enable_stats_IxNetwork $ixnetwork_root]

    #Run Traffic
    set cmdOutputsLoc ""
    if {[_run_traffic_IxNetwork cmdOutputsLoc $ixnetwork_root $run_time \
                                $exec_cmds $uut $tr] != $SUCCESS} {
        return $returnList
    }

    #Initialize Variables
    set txPktsLoc 0; set rxPktsLoc 0;
    set avgLatencyLoc 0; set minLatencyLoc 0; set maxLatencyLoc 0

    if {0} {
    #Get Tx Stats
    if {[_get_txPkts_IxNetwork txPktsLoc ixNetworkStreamCountLoc \
                               $ixnetwork_root] != $SUCCESS} {
        return $returnList
    }

    #Get Rx Stats
    if {[_get_rxPkts_IxNetwork rxPktsLoc $ixnetwork_root] != $SUCCESS} {
        return $returnList
    }
    }

    # Adding new proc as a work around for Ixia Stats update error
    sleep 5
    if {[_get_txRxPkts_IxNetwork txPktsLoc rxPktsLoc ixNetworkStreamCountLoc \
                                 $ixnetwork_root] != $SUCCESS} {
        return $returnList
    }

    #Get Latency Stats
    if {$latency == 1} {
        if {[_get_latency_IxNetwork avgLatencyLoc minLatencyLoc maxLatencyLoc \
                                    $ixnetwork_root $debug] != $SUCCESS} {
            return $returnList
        }
    }

    return 1
} ; # End of Proc _run_IxNetwork_test

######################################################################
##Procedure Header
# Name:
#   perfUtils::_run_IxNetwork_test2
#
# Purpose:
#    run one iteration of IxNetwork, using high-level api
#
# Synopsis:
#    _run_IxNetwork_test2 args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc runs IxNetwork test(2). using high-level api
######################################################################
proc perfUtils::_run_IxNetwork_test2 {txPkts rxPkts numPkts avgLatency \
minLatency maxLatency cmdOutputs returnList txPorts txStreams txStreamSets \
tx_mode rxPorts mtxPorts mtxStreams mtxStreamSets mtxOifs mtxOifSets \
mtx_ports run_time curRate uds_count2 min_cap_pkts numRxPorts numMrxPorts \
exec_cmds uut tr latency latency_detail debug} {

    set SUCCESS 1
    upvar $txPkts txPktsLoc
    upvar $rxPkts rxPktsLoc
    upvar $numPkts numPktsLoc
    upvar $avgLatency avgLatencyLoc
    upvar $minLatency minLatencyLoc
    upvar $maxLatency maxLatencyLoc
    upvar $cmdOutputs cmdOutputsLoc
    upvar $returnList returnListLoc

    #Set Traffic Rate
    #Note: can use same _set_curRate proc with IxExplorer method
    if {[_set_curRate_IxExplorer $txPorts $txStreamSets $tx_mode $mtxPorts \
         $mtxStreams $mtxOifs $mtx_ports $numMrxPorts $curRate] != $SUCCESS} {
        return $returnList
    }

    #Run Traffic
    set cmdOuputsLoc ""
    #Note: can use same _run_traffic proc with IxExplorer method
    if {[_run_traffic_IxExplorer cmdOutputsLoc $txPorts $rxPorts $run_time \
                                 $exec_cmds $uut $tr] != $SUCCESS} {
        return $returnList
    }

    #sleep 20 second, since ixNetwork seems to have heavy time delay
    after 20000

    #Get Tx Stats
    set txPktsLoc [_get_txPkts_IxNetwork2 $txPorts $txStreamSets $mtxPorts \
                   $mtxStreamSets $mtxOifSets $mtx_ports $debug]

    #Get Rx Stats
    set rxPktsLoc [_get_rxPkts_IxNetwork2 $rxPorts $uds_count2 $debug]

    #Get Latency Stats
    set numPktsLoc 0;
    set avgLatencyLoc 0; set minLatencyLoc 0; set maxLatencyLoc 0
    if {$latency == 1} {
        if {[_get_latency_IxNetwork2 numPktsLoc avgLatencyLoc minLatencyLoc \
              maxLatencyLoc returnListLoc $rxPorts $min_cap_pkts $numRxPorts\
              $debug $latency_detail  $txStreamSets $txPorts] != $SUCCESS} {
            #return $returnList
            #rupan note: here actually should return $returnList; yet if so,
            #status of returnList is 0, and the Ndr will not get recorded in
            #the script which uses findNdr method.
            #so instead we return 1, so latency is 0 in the record, rather than
            #expected value, and in the log there is note to explain rx_mode
            #should be set capture_and_measure if wanting calculate latency.
            return 1
        }
    }

    return 1
} ; # End of Proc _run_IxNetwork_test2


######################################################################
##Procedure Header
# Name:
#    _set_curRate_IxExplorer
#
# Purpose:
#    set the traffic rate for the next iteration on IxExplorer.
#
# Synopsis:
#    _set_curRate_IxExplorer args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc sets the traffic rate for the next iteration on IxExplorer
######################################################################
proc _set_curRate_IxExplorer {txPorts txStreamSets tx_mode mtxPorts \
mtxStreams mtxOifs mtx_ports numMrxPorts curRate} {
    #Set traffic rate for all streams
    set tempRate $curRate; set SUCCESS 1
    foreach port $txPorts txStreamSet $txStreamSets {
        if {$tx_mode == "advanced"} {
            set numStreams [llength $txStreamSet]
            set curRate [expr {$tempRate/$numStreams}]
        }
        foreach stream $txStreamSet {
            set traffic_status [ixia::traffic_config        \
                -mode                       modify          \
                -stream_id                  $stream         \
                -port_handle                $port           \
                -rate_pps                   $curRate        ]
            if {[keylget traffic_status status] != $SUCCESS} {
                set diag "Couldn't configure base stream on $port"
                ats_log -error $diag
                ats_log -error "[keylget traffic_status log]"
                ats_results -result fail
            }
        }
    }

    if {[info exists mtx_ports]} {
        set numMStreams [llength mtxStreams]
        set curRate $tempRate
        if {$tx_mode == "advanced"} {
            set curRate [expr {$tempRate/$numMStreams}]
        }
        foreach port $mtxPorts {
            foreach stream $mtxStreams oif $mtxOifs {
                set traffic_status [ixia::traffic_config    \
                    -mode               modify              \
                    -stream_id          $stream             \
                    -port_handle        $port               \
                    -rate_pps           [expr {($curRate/$oif)*$numMrxPorts}]]
                if {[keylget traffic_status status] != $SUCCESS} {
                     set diag "Couldn't configure base stream on $port"
                     ats_log -error $diag
                     ats_log -error "[keylget traffic_status log]"
                     ats_results -result fail
                }
            }
        }
    }

    set diag "Now trying $curRate pps (per port @ each stream)... "
    ats_log -diag $diag

    return 1
} ; # End of Proc _set_curRate_IxExplorer

######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_txPkts_IxExplorer
#
# Purpose:
#    get the traffic stats for IxExplorer and returns transmitted packets.
#
# Synopsis:
#    _get_txPkts_IxExplorer args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the traffic stats for IxExplorer
#    and returns transmitted packets
######################################################################
proc perfUtils::_get_txPkts_IxExplorer {txPorts txStreamSets mtxPorts \
mtxStreamSets mtxOifSets mtx_ports debug} {

    #Initialize variables
    set txPkts 0
    set _txPkts 0
    set mtxPkts 0
    set _mtxPkts 0
    set success 1

    #Get the total number of packets sent
    #here calculate the actual number of packets sent across all streams
    foreach txPort $txPorts txStreamSet $txStreamSets {
         foreach txStream $txStreamSet {
             set txStats [ixia::traffic_stats -port_handle $txPort \
                                              -mode stream -stream $txStream]
             if {[keylget txStats status] != $success} {
                 set diag "Couldn't get TX stats on $txPort : $txStream"
                 ats_results -diag $diag
                 ats_log -diag $diag
                 if {$debug == 1} {
                     ats_log -diag "txStats: $txStats"
                 }
                 ats_results -result fail
             }
             if { [catch {
                 set txPkts [expr { 1.0*$txPkts + \
                     [keylget txStats $txPort.stream.$txStream.tx.total_pkts]}]
                 #For debug only
                 set _txPkts [expr {1.0*$_txPkts + \
                     [keylget txStats $txPort.stream.$txStream.tx.total_pkts]}]
             } errmsg ] } {
                 ats_log -info "txStats: $txStats"
                 set diag "Couldn't get TX stats on $txPort : $txStream"
                 ats_results -result fail
             }
         }
         if {$debug == 1} {
            ats_log -diag "$txPort - txPkts (mtx pkts included) $_txPkts";
            set _txPkts 0
         }
     }

     #If multicast streams exists, adjust the total number of replicated packets
     if {[info exists mtx_ports]} {
         foreach mtxPort $mtxPorts mtxStreamSet $mtxStreamSets \
                 mtxOifSet $mtxOifSets {
             foreach mtxStream $mtxStreamSet mtxOif $mtxOifSet {
                 set mtxStats [ixia::traffic_stats -port_handle $mtxPort \
                                               -mode stream -stream $mtxStream]
                 if {[keylget mtxStats status] != $success} {
                     set diag "Couldn't get TX stats on $mtxPort : $mtxStream"
                     ats_results -diag $diag
                     ats_log -diag $diag
                     if {$debug == 1} {
                         ats_log -diag "mtxStats: $mtxStats"
                     }
                     ats_results -result fail
                 }
                 if { [catch {
                     set extraPkts  [keylget mtxStats \
                                 $mtxPort.stream.$mtxStream.tx.total_pkts]
                     set mtxPkts [expr {$mtxPkts + (1.0 * $mtxOif * [keylget mtxStats\
                       $mtxPort.stream.$mtxStream.tx.total_pkts]) - $extraPkts}]
                 } errmsg ] } {
                     ats_log -info "mtxStats: $mtxStats"
                     set diag "Couldn't get TX stats on $mtxPort : $mtxStream"
                     ats_results -result fail
                 }
                 #For debug only
                 set _mtxPkts [expr {$_mtxPkts + \
                   [keylget mtxStats $mtxPort.stream.$mtxStream.tx.total_pkts]}]

             }
             if {$debug == 1} {
              ats_log -diag "$mtxPort - mtxPkts x mtxOif - $_mtxPkts x $mtxOif"
              set _mtxPkts 0
             }

         }
     }

     #Calculate the total number of packets expected to be received on rxPorts,
     set txPkts [expr { $txPkts + $mtxPkts}]
     if {$txPkts <= 1.0} {
         set diag "txPkts 0 - Please check your streams OR API call params "
         ats_log -diag $diag
     }

     return $txPkts

} ; # End of Proc _get_rxPkts_IxExplorer

######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_rxPkts_IxExplorer
#
# Purpose:
#    get the Rx stats for IxExplorer and return pkts received
#
# Synopsis:
#    _get_rxPkts_IxExplorer args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the Rx stats for IxExplorer and return pkts received
######################################################################
proc perfUtils::_get_rxPkts_IxExplorer {rxPorts uds_count debug} {

    #Initialize Rx variables
    set rxPkts 0 ; set _rxPkts 0
    set success 1

    #Get the total number of interesting packets received on RxPorts
    foreach rxPort $rxPorts {
        set rxStats [ixia::traffic_stats -port_handle $rxPort]
        if {[keylget rxStats status] != $success} {
            set diag "Couldn't get RX stats on $rxPort"
            ats_results -diag $diag
            ats_log -diag $diag
            if {$debug == 1} {
                 ats_log -diag "rxStats: $rxStats"
            }
        }
        if { [catch {
            set rxPkts [expr {1.0*$rxPkts + \
                    [keylget rxStats $rxPort.aggregate.rx.$uds_count]}]
            set _rxPkts [expr {1.0* $_rxPkts + \
                    [keylget rxStats $rxPort.aggregate.rx.$uds_count]}]
        } errmsg ] } {
            ats_log -info "rxStats: $rxStats"
            set diag "Couldn't get RX stats on $rxPort"
            ats_results -result fail
        }
        if {$debug == 1} {
            ats_log -diag "$rxPort - rxPkts - $_rxPkts";
            set _rxPkts 0
        }
    }
    return $rxPkts

} ; # End of Proc _get_rxPkts_IxExplorer

######################################################################
##Procedure Header
# Name:
#   perfUtils::_get_latency_IxExplorer
#
# Purpose:
#    get the latencies on IxExplorer and upvars it
#
# Synopsis:
#    _get_latency_IxExplorer args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the latencies on IxExplorer and upvars it
######################################################################
proc perfUtils::_get_latency_IxExplorer {numPkts avgLatency minLatency \
maxLatency returnList rxPorts min_cap_pkts numRxPorts debug latency_detail} {

    upvar $numPkts numPktsLocal
    upvar $avgLatency avgLatencyLocal
    upvar $minLatency minLatencyLocal
    upvar $maxLatency maxLatencyLocal
    upvar $returnList returnListLocal
    set numPktsLocal 0; set _numPkts 0
    set avgLatencyLocal 0; set _avgLatency 0
    set minLatencyLocal 0; set _minLatency 0
    set maxLatencyLocal 0; set _maxLatency 0
    set success 1; set failure 0

    #puts "enter _get_latency_IxExplorer"
    foreach rxPort $rxPorts {
        set rxPktStats [ixia::packet_stats -port_handle $rxPort \
                              -format none -chunk_size 8000000]
        if {[keylget rxPktStats status] != $success} {
            set diag "Couldn't get RX packet stats on $rxPort"
            ats_results -diag $diag
            ats_log -diag $diag
        }
        #set rxpkt [keylget rxStats $rxPort.aggregate.rx.$uds_count]
        ats_log -info "ixia rx_status:$rxPktStats"
        if {[keylget rxPktStats $rxPort.aggregate.num_frames] < $min_cap_pkts \
         || [keylget rxPktStats $rxPort.aggregate.num_frames] == "N/A"} {
            keylset returnListLocal status $failure
            keylset returnListLocal log "[_error 8] - Pkts catured \
            [keylget rxPktStats $rxPort.aggregate.num_frames] \
            Min number of Pkts required $min_cap_pkts"
            return 0
        }
        set numPktsLocal [expr {$numPktsLocal + \
                            [keylget rxPktStats $rxPort.aggregate.num_frames]}]
        set _numPkts [expr {$_numPkts + \
                            [keylget rxPktStats $rxPort.aggregate.num_frames]}]
        set avgLatencyLocal [expr {$avgLatencyLocal + \
                       [keylget rxPktStats $rxPort.aggregate.average_latency]}]
        set _avgLatency [expr {$_avgLatency + \
                       [keylget rxPktStats $rxPort.aggregate.average_latency]}]
        set minLatencyLocal [expr {$minLatencyLocal + \
                           [keylget rxPktStats $rxPort.aggregate.min_latency]}]
        set _minLatency [expr {$_minLatency + \
                           [keylget rxPktStats $rxPort.aggregate.min_latency]}]
        set maxLatencyLocal [expr {$maxLatencyLocal + \
                           [keylget rxPktStats $rxPort.aggregate.max_latency]}]
        set _maxLatency [expr {$_maxLatency + \
                           [keylget rxPktStats $rxPort.aggregate.max_latency]}]

        if {$debug == 1} {
            ats_log -diag "$rxPort- numPkts - $_numPkts\
                           avgLatency - $_avgLatency\
                           minLatency - $_minLatency\
                           maxLatency - $_maxLatency"
            set _numPkts 0
            set _avgLatency 0
            set _minLatency 0
            set _maxLatency 0
        }
        if {$latency_detail > 0} {
            ats_log -diag "Latency detail enabled @ $latency_detail %"

            scan $rxPort "%d/%d/%d" ix_c ix_l ix_p
            capture get $ix_c $ix_l $ix_p

            set NOW [clock format [clock seconds] -format {%m%d%y%H%M%S}]
            set file_name "Latency_$latency_detail.$ix_c$ix_l$ix_p$NOW.latency"
            set fd1 [open $file_name "w"]

            set numCapture [capture cget -nPackets]
            if { [captureBuffer get $ix_c $ix_l $ix_p 1 $numCapture] } {
                ats_log -diag "Failed to get captureBuffer"
            }
            captureBuffer getStatistics
            puts $fd1 "Per packet latency @ port $ix_c $ix_l $ix_p"
            set numFrames [captureBuffer cget -numFrames]
            set averageLatency [captureBuffer cget -averageLatency]
            set minLatency [captureBuffer cget -minLatency]
            set maxLatency [captureBuffer cget -maxLatency]
            set standardDeviation [captureBuffer cget -standardDeviation]
            set averageDeviation [captureBuffer cget -averageDeviation]

            puts $fd1 "numFrames - $numFrames |\
                       averageLatency - $averageLatency |\
                       minLatency - $minLatency |\
                       maxLatency - $maxLatency |\
                       standardDeviation $standardDeviation |\
                       averageDeviation $averageDeviation "

            for {set i 1} { $i <= $numFrames } { incr i } {
                captureBuffer getframe $i
                set frame_latency [captureBuffer cget -latency]
                set frame_time [captureBuffer cget -timestamp]
                puts $fd1 "$frame_time - $frame_latency"
            }
            close $fd1
        }
    }

    set avgLatencyLocal [expr {$avgLatencyLocal/$numRxPorts}]
    set minLatencyLocal [expr {$minLatencyLocal/$numRxPorts}]
    set maxLatencyLocal [expr {$maxLatencyLocal/$numRxPorts}]

    return 1

} ; # End of Proc _get_latency_IxExplorer

######################################################################
##Procedure Header
# Name:
#    perfUtils::_run_traffic_IxExplorer
#
# Purpose:
#    runs the traffic for the run_time seconds
#    and upvars cmd output on IxExplorer
#
# Synopsis:
#    _get_latency_IxExplorer args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc runs the traffic for the run_time seconds
#    and upvars cmd output on IxExplorer
######################################################################
proc perfUtils::_run_traffic_IxExplorer {cmdOutputs txPorts rxPorts run_time \
exec_cmds uut tr} {

    upvar $cmdOutputs cmdOutputsLocal
    set allPorts [concat $rxPorts $txPorts]
    #Clearing of stats need to be a one statement as below,
    #otherwise latency will mess up
    #debug 1
    ixia::traffic_control -port_handle $allPorts -action clear_stats

    #start the packet capture
    foreach port $rxPorts {
        ixia::packet_control -port_handle $port -action start
    }

    #start the traffic
    set STC_DISABLE_ARP 0
    global env
    if { [info exists env(USE_STC)] && $env(USE_STC) } {
        if { [info exists env(STC_DISABLE_ARP)] && $env(STC_DISABLE_ARP) } {
            set STC_DISABLE_ARP 1
            ats_log -info "run_traffic_IxExplorer: disabling ARP for STC -action run"
        }
    }
    foreach port $txPorts {
        if {$STC_DISABLE_ARP} {
            ixia::traffic_control -port_handle $port -action run
        } else {
            ixia::traffic_control -port_handle $port -action run
        }
    }

    #Wait for half the test run time
    sleep [expr {$run_time/2.0}]

    #Execute any commands for debug or results
    set cmdOutputsLocal {}
    foreach cmd $exec_cmds {
        lappend cmdOutputsLocal [$uut exec $cmd]
        if { $tr != "" } {
            $tr exec $cmd
        }
        # sleep a while between each show command, 
        # to reduce the impact on resource using
        sleep 3
    }

    #Wait for another half the test run time
    sleep [expr {$run_time/2.0}]

    #stop the traffic
    foreach port $txPorts {
        ixia::traffic_control -port_handle $port -action stop
    }

    #stop the packet capture
    foreach port $rxPorts {
        ixia::packet_control -port_handle $port -action stop
    }

    $uut exec "show platform hardware qfp active statistics drop clear"
    if { $tr != "" } {
        $tr exec "show platform hardware qfp active statistics drop clear"
    }
    #Wait for 5 seconds before starting to collect data
    sleep 5

    return 1

} ; # End of Proc _run_traffic_IxExplorer


######################################################################
##Procedure Header
# Name:
#   perfUtils::_set_curRate_IxNetwork
#
# Purpose:
#    set the traffic rate for the next iteration on IxNetwork
#
# Synopsis:
#    _set_curRate_IxNetwork args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc sets the traffic rate for the next iteration on IxNetwork
######################################################################
proc perfUtils::_set_curRate_IxNetwork {root curRate} {

    set traffic $root/traffic
    #debug 1
    # Set rate
    set trafficItems [::ixNet getList $root/traffic trafficItem]
    foreach {trafficItem} $trafficItems {
        ::ixNet setAttribute $trafficItem/rateOptions -packetsPerSecond $curRate
        ::ixNet setAttribute $trafficItem/rateOptions -rateMode packetsPerSecond
    }
    ::ixNet commit

    #_ixnetwork_set_rate $curRate
    set genTraffic [ixNet setAtt $traffic -refreshLearnedInfoBeforeApply true]
    ixNet commit
    set apply [::ixNet exec apply $traffic]

    return 1

} ; # End of Proc _set_curRate_IxNetwork

######################################################################
##Procedure Header
# Name:
#    perfUtils::_enable_stats_IxNetwork
#
# Purpose:
#    enable traffic stats on IxNetwork
#
# Synopsis:
#    _enable_stats_IxNetwork args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc enables traffic stats on IxNetwork
######################################################################
proc perfUtils::_enable_stats_IxNetwork {root} {

    # Enable stats
    #debug 1
    set statistic    $root/statistics
    set statViewList [ixNet getList $statistic trafficStatViewBrowser]
    set indexOftraffStats [lsearch -regexp $statViewList "Traffic Statistics"]
    set trafficStats [lindex $statViewList $indexOftraffStats]
    ixNet setAttr $trafficStats -enabled true
    ixNet commit

    return 1

} ; # End of Proc _enable_stats_IxNetwork

######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_txPkts_IxNetwork
#
# Purpose:
#    get the Tx stats for IxNetwork and return transmitted pkts
#
# Synopsis:
#    _get_txPkts_IxNetwork args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the Tx stats for IxNetwork and return transmitted pkts
######################################################################
proc perfUtils::_get_txPkts_IxNetwork {txPkts ixNetworkStreamCount root} {

    upvar $txPkts txPktsLocal
    upvar $ixNetworkStreamCount ixNetworkStreamCountLoc

    #Initialize Rx variables
    set txPkts 0
    set success 1

    set statistic $root/statistics
    set statViewList [ixNet getList $statistic trafficStatViewBrowser]
    set indexOftraffStats [lsearch -regexp $statViewList "Traffic Statistics"]
    set trafficStats [lindex $statViewList $indexOftraffStats]
    ixNet setAttr $trafficStats -enabled true
    ixNet commit

    # Get stats
    set rows [ixNet getList $trafficStats row]
    set framesDelta 0
    set totalLat 0
    set ixNetworkStreamCountLoc 0

    foreach row $rows {
        set stats [ixNet getList $row cell]
        set curTxFrames [ixNet getAttr \
            [lindex $stats [lsearch -regexp $stats {Tx Frames}]] -statValue]
        set txPktsLocal [mpexpr $txPktsLocal + $curTxFrames]
        incr ixNetworkStreamCountLoc
    }

    #puts "txPkts $txPktsLocal"
    #puts "ixNetworkStreamCountLoc $ixNetworkStreamCountLoc"

    return 1

} ; # End of Proc _get_txPkts_IxNetwork

######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_txPkts_IxNetwork2
#
# Purpose:
#    get the Tx stats for IxNetwork and return transmitted pkts
#    using high-level api
#
# Synopsis:
#    _get_txPkts_IxNetwork2 args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the Tx stats for IxNetwork and return transmitted pkts
#    using high-level api
######################################################################
proc perfUtils::_get_txPkts_IxNetwork2 {txPorts txStreamSets mtxPorts \
mtxStreamSets mtxOifSets mtx_ports debug} {

    #Initialize variables
    set txPkts 0
    set _txPkts 0
    set mtxPkts 0
    set _mtxPkts 0
    set success 1

    #Get the total number of packets sent,
    #here calculate the actual number of packets sent across all streams
    foreach txPort $txPorts txStreamSet $txStreamSets {
        #IxNetwork can only get aggregate count with this method,
        #so not "foreach txStream $txStreamSet", but just one
        #foreach txStream $txStreamSet {
            set txStats [ixia::traffic_stats -port_handle $txPort \
                                             -traffic_generator ixnetwork_540]
            if {$debug == 1} {
                set key $txPort.aggregate.tx
                set aggregate_keys [keylkeys txStats $key]
                foreach aggregate_key $aggregate_keys {
                    ats_log -info "[format "%5s %10s" $aggregate_key \
                    [keylget txStats $key.$aggregate_key]]"
                }
            }
            set txPkts [expr {$txPkts + \
                   [keylget txStats $txPort.aggregate.tx.scheduled_pkt_count]}]
            #For debug only
            set _txPkts [expr {$_txPkts + \
                   [keylget txStats $txPort.aggregate.tx.scheduled_pkt_count]}]
            if {[keylget txStats status] != $success} {
                set diag "Couldn't get TX stats on $txPort (aggregate)"
                ats_results -diag $diag
                ats_log -diag $diag
                ats_results -result fail
            }
        #}
        if {$debug == 1} {
           ats_log -diag "$txPort - txPkts (mtx pkts included) $_txPkts";
           set _txPkts 0
        }
    }

    #If multicast streams exists, adjust the total number of replicated packets
    if {[info exists mtx_ports]} {
        foreach mtxPort $mtxPorts mtxStreamSet $mtxStreamSets \
                mtxOifSet $mtxOifSets {
            #IxNetwork can only get aggregate count with this method,
            #so not "foreach txStream $txStreamSet", but just one
            set firstTime 1
            foreach mtxStream $mtxStreamSet mtxOif $mtxOifSet {
                if { $firstTime == 1 } {
                    set mtxStats [ixia::traffic_stats -port_handle $mtxPort \
                                              -traffic_generator ixnetwork_540]
                    set extraPkts  [keylget mtxStats \
                                    $mtxPort.aggregate.tx.scheduled_pkt_count]
                    set mtxPkts [expr {$mtxPkts + (1.0 * $mtxOif * [keylget mtxStats \
                      $mtxPort.aggregate.tx.scheduled_pkt_count]) - $extraPkts}]
                    #For debug only
                    set _mtxPkts [expr {$_mtxPkts + \
                  [keylget mtxStats $mtxPort.aggregate.tx.scheduled_pkt_count]}]

                    if {[keylget mtxStats status] != $success} {
                        set diag "Couldn't get TX stats on $mtxPort (aggregate)"
                        ats_results -diag $diag
                        ats_log -diag $diag
                        ats_results -result fail
                    }
                }
                set firstTime 0
            }
            if {$debug == 1} {
               ats_log -diag "$mtxPort - mtxPkts x mtxOif - $_mtxPkts x $mtxOif";
               set _mtxPkts 0
            }
        }
    }

    #Calculate the total number of packets expected to be received on rxPorts,
    set txPkts [expr { $txPkts + $mtxPkts}]
    if {$txPkts <= 1.0} {
        set diag "txPkts 0 - Please check your streams OR API call params "
        ats_log -diag $diag
    }
    return $txPkts

} ; # End of Proc _get_txPkts_IxNetwork2


######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_txRxPkts_IxNetwork
#
# Purpose:
#    get the Rx and TX stats for IxNetwork and return pkts received
#
# Synopsis:
#    _get_txPkts_IxNetwork2 args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the Rx and TX stats for IxNetwork and return pkts received
#    This proc is workaround for IxNW status update error
#    The code s for one port 10 GE card.  For the XM8 cards,
#    you don't need the workaround code.
#    The old one port 10GE card does not support the port level filtering
#    for the stats, so the stats update maybe lagging.
######################################################################
proc perfUtils::_get_txRxPkts_IxNetwork {txPkts rxPkts ixNetworkStreamCount \
root} {

    upvar $txPkts txPktsLocal
    upvar $rxPkts rxPktsLocal
    upvar $ixNetworkStreamCount ixNetworkStreamCountLoc

    #Initialize Rx variables
    set txPkts 0
    set rxPkts 0
    set success 1

    set statistic $root/statistics
    set statViewList [ixNet getList $statistic trafficStatViewBrowser]
    set indexOftraffStats [lsearch -regexp $statViewList "Traffic Statistics"]
    set trafficStats [lindex $statViewList $indexOftraffStats]
    ixNet setAttr $trafficStats -enabled true
    ixNet commit


    ### TK debug
    set timeout 0
    set error "false"
    set continueFlag "true"

    while {$continueFlag == "true"} {
        set continueFlag "false"
        set rows [ixNet getList $trafficStats row]
        set ixNetworkStreamCountLoc 0

        foreach row $rows {
            set stats [ixNet getList $row cell]
            set curTxFrames [ixNet getAttr [lindex $stats \
                            [lsearch -regexp $stats {Tx Frames}]] -statValue]
            set curRxFrames [ixNet getAttr [lindex $stats \
                            [lsearch -regexp $stats {Rx Frames}]] -statValue]
            set curTxFrameRate [ixNet getAttr [lindex $stats \
                        [lsearch -regexp $stats {Tx Frame Rate}]] -statValue]
            set curRxFrameRate [ixNet getAttr [lindex $stats \
                        [lsearch -regexp $stats {Rx Frame Rate}]] -statValue]
            set curLossPercent [ixNet getAttr [lindex $stats \
                               [lsearch -regexp $stats {Loss %}]] -statValue]
            #puts "curTxFrameRate = $curTxFrameRate \
            #curRxFrameRate = $curRxFrameRate curLossPercent = $curLossPercent"

            if { $curTxFrameRate != 0 || $curRxFrameRate != 0 } {
                set continueFlag "true"
                after 1000
               incr timeout
                if {$timeout == 240} {
                    set continueFlag "false"
                    set error "true"
                }
            } else {

            if {$curTxFrames == {} || $curRxFrames == {} || \
                $curTxFrameRate == {} || $curRxFrameRate == {} || \
                $curLossPercent == {} } {
                ### pause for 1 second
                set continueFlag "true"
                after 1000
                incr timeout
                if {$timeout == 240} {
                    set continueFlag "false"
                    set error "true"
                }
            } else {
                set txPktsLocal [expr {$txPktsLocal + $curTxFrames}]
                set rxPktsLocal [expr {$rxPktsLocal + $curRxFrames}]
                incr ixNetworkStreamCountLoc

            }
            }
        }
    }
    if {$error == "true"} {
        #puts "Ixia Error:  failed to get either Tx Frames or Rx Frames count \
        #      after 180 seconds"
    }

    #puts "txPkts $txPktsLocal rxPkts $rxPktsLocal"
    #puts "ixNetworkStreamCountLoc $ixNetworkStreamCountLoc"

    return 1

} ; # End of Proc _get_txPkts_IxNetwork



######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_rxPkts_IxNetwork
#
# Purpose:
#    get the Rx stats for IxNetwork and return pkts received
#
# Synopsis:
#    _get_rxPkts_IxNetwork args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the Rx stats for IxNetwork and return pkts received
######################################################################
proc perfUtils::_get_rxPkts_IxNetwork {rxPkts root} {

    upvar $rxPkts rxPktsLocal

    #Initialize Rx variables
    set rxPkts 0
    set success 1

    set statistic $root/statistics
    set statViewList [ixNet getList $statistic trafficStatViewBrowser]
    set indexOftraffStats [lsearch -regexp $statViewList "Traffic Statistics"]
    set trafficStats [lindex $statViewList $indexOftraffStats]
    ixNet setAttr $trafficStats -enabled true
    ixNet commit

    # Get stats
    set rows [ixNet getList $trafficStats row]
    set framesDelta 0
    set totalLat 0
    set ixNetworkStreamCount 0

    foreach row $rows {
        set stats [ixNet getList $row cell]
        set curRxFrames [ixNet getAttr [lindex $stats \
                        [lsearch -regexp $stats {Rx Frames}]] -statValue]
        set rxPktsLocal [mpexpr $rxPktsLocal + $curRxFrames]
        incr ixNetworkStreamCount
    }

    #puts "rxPkts $rxPktsLocal"
    return 1

} ; # End of Proc _get_rxPkts_IxNetwork


######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_rxPkts_IxNetwork2
#
# Purpose:
#    get the Rx stats for IxNetwork and return pkts received
#    using high-level api
#
# Synopsis:
#    _get_rxPkts_IxNetwork2 args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 -  failure
#
# Description:
#    This Proc gets the Rx stats for IxNetwork and return pkts received
#    using high-level api
######################################################################
proc perfUtils::_get_rxPkts_IxNetwork2 {rxPorts uds_count2 debug} {
    #Initialize Rx variables
    set rxPkts 0 ; set _rxPkts 0
    set success 1
    set uds_count2 "uds2_frame_count"
    #debug 1
    #Get the total number of interesting packets received on RxPorts
    foreach rxPort $rxPorts {
        set rxStats [ixia::traffic_stats -port_handle $rxPort \
                                         -traffic_generator ixnetwork_540]
        if { $debug == 1 } {
            set key $rxPort.aggregate.rx
            set aggregate_keys [keylkeys rxStats $key]
            foreach aggregate_key $aggregate_keys {
                ats_log -info "[format "%5s %10s" $aggregate_key \
                [keylget rxStats $key.$aggregate_key]]"
            }
        }

        if {[keylget rxStats status] != $success} {
            set diag "Couldn't get RX stats on $rxPort"
            ats_results -diag $diag
            ats_log -diag $diag
        }
        set rxPkts [expr {1.0*$rxPkts + \
                   [keylget rxStats $rxPort.aggregate.rx.$uds_count2]}]
        set _rxPkts [expr {1.0* $_rxPkts + \
                    [keylget rxStats $rxPort.aggregate.rx.$uds_count2]}]
        if {$debug == 1} {
           ats_log -diag "$rxPort - rxPkts - $_rxPkts";
           set _rxPkts 0
        }
    }
    return $rxPkts

} ; # End of Proc _get_rxPkts_IxNetwork2


######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_latency_IxNetwork
#
# Purpose:
#    get the latencies on IxNetwork and upvars it
#
# Synopsis:
#    _get_latency_IxNetwork args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc gets the latencies on IxNetwork and upvars it
######################################################################
proc perfUtils::_get_latency_IxNetwork {avgLatency minLatency maxLatency root \
debug} {

    upvar $avgLatency avgLatencyLocal
    upvar $minLatency minLatencyLocal
    upvar $maxLatency maxLatencyLocal

    set avgLatencyLocal 0
    set minLatencyLocal 0
    set maxLatencyLocal 0

    #Initialize Rx variables
    set avgLatency 0
    set success 1

    set statistic $root/statistics
    set statViewList [ixNet getList $statistic trafficStatViewBrowser]
    set indexOftraffStats [lsearch -regexp $statViewList "Traffic Statistics"]
    set trafficStats [lindex $statViewList $indexOftraffStats]
    ixNet setAttr $trafficStats -enabled true
    ixNet commit

    # Get stats
    set rows [ixNet getList $trafficStats row]
    set framesDelta 0
    set totalLat 0; set curMinLat 0; set curMaxLat 0; set curAvgLat 0
    set ixNetworkStreamCount 0
    set rx_pkt 0


    foreach row $rows {
        set stats [ixNet getList $row cell]
        set rx_pkts   [ixNet getAttr [lindex $stats \
                       [lsearch -regexp $stats {Rx Frames}]] -statValue]
        if {$rx_pkts != 0 } {
            set curAvgLat [ixNet getAttr [lindex $stats \
                     [lsearch -regexp $stats {Avg Latency \(ns\)}]] -statValue]
            set curMinLat [ixNet getAttr [lindex $stats \
                     [lsearch -regexp $stats {Min Latency \(ns\)}]] -statValue]
            set curMaxLat [ixNet getAttr [lindex $stats \
                     [lsearch -regexp $stats {Max Latency \(ns\)}]] -statValue]
            set avgLatencyLocal [mpexpr $avgLatencyLocal + $curAvgLat]
            set minLatencyLocal [mpexpr $minLatencyLocal + $curMinLat]
            set maxLatencyLocal [mpexpr $maxLatencyLocal + $curMaxLat]
            incr ixNetworkStreamCount
           #puts "Stream: $ixNetworkStreamCount curMinLat:$curMinLat \
           #      curMaxLat:$curMaxLat curAvgLat:$curAvgLat"
           #puts "Stream:$ixNetworkStreamCount minLatencyLocal:$minLatencyLocal\
           #maxLatencyLocal:$maxLatencyLocal avgLatencyLocal:$avgLatencyLocal"
        }
    }
    set avgLatencyLocal [{expr $avgLatencyLocal / $ixNetworkStreamCount}]
    set minLatencyLocal [{expr $minLatencyLocal / $ixNetworkStreamCount}]
    set maxLatencyLocal [{expr $maxLatencyLocal / $ixNetworkStreamCount}]

    #puts "Final Stream: $ixNetworkStreamCount minLatencyLocal:$minLatencyLocal\
    #      maxLatencyLocal:$maxLatencyLocal avgLatencyLocal:$avgLatencyLocal"
    ###
    if {$debug == 1} {
        ats_log -diag "\
               avgLatency - $avgLatencyLocal\
               minLatency - $minLatencyLocal\
               maxLatency - $maxLatencyLocal"
        set _avgLatency 0
        set _minLatency 0
        set _maxLatency 0
    }
    ###

    #puts "AvgLatency $avgLatencyLocal"

    return 1

} ; # End of Proc _get_latency_IxNetwork

######################################################################
##Procedure Header
# Name:
#    perfUtils::_get_latency_IxNetwork2
#
# Purpose:
#    get the latencies on IxNetwork and upvars it using high-level api
#
# Synopsis:
#    _get_latency_IxNetwork2 args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc gets the latencies on IxNetwork and upvars it
#    using high-level api
######################################################################
proc perfUtils::_get_latency_IxNetwork2 {numPkts avgLatency minLatency \
maxLatency returnList rxPorts min_cap_pkts numRxPorts debug latency_detail \
txStreamSets txPorts} {
    upvar $numPkts numPktsLocal
    upvar $avgLatency avgLatencyLocal
    upvar $minLatency minLatencyLocal
    upvar $maxLatency maxLatencyLocal
    upvar $returnList returnListLocal
    set numPktsLocal 0; set _numPkts 0
    set avgLatencyLocal 0; set _avgLatency 0
    set minLatencyLocal 0; set _minLatency 0
    set maxLatencyLocal 0; set _maxLatency 0
    set success 1; set failure 0

    set traffic_status [::ixia::traffic_control    \
        -action                 run                    \
        -traffic_generator      ixnetwork_540          \
    ]
    after 5000
    set traffic_status [::ixia::traffic_control    \
        -action                 stop                   \
        -traffic_generator      ixnetwork_540          \
    ]
    after 15000

    set flow_traffic_status [::ixia::traffic_stats    \
        -mode                   flow                      \
        -traffic_generator      ixnetwork_540             \
    ]
    set num_flow 0
    if { [ catch {
        set flows [keylget flow_traffic_status flow]
    } err_msg ] } {
        keylset returnListLocal status $failure
        ats_log -info "[_error 10] - fail to get avg_delay without measure flow"
        return 0
    }
    foreach flow [keylkeys flows] {
        set num_flow [expr {$num_flow + 1}]
        set flow_key [keylget flow_traffic_status flow.$flow]
        if { [keylget flow_traffic_status flow.$flow.rx.avg_delay] == "N/A" } {
             keylset returnListLocal status $failure
             ats_log -info "[_error 10] - \
                            fail to get avg_delay without measure flow"
             return 0
        }
        set numPktsLocal [expr {$numPktsLocal + \
                         [keylget flow_traffic_status flow.$flow.rx.total_pkts]}]
        set _numPkts [expr {$_numPkts + \
                         [keylget flow_traffic_status flow.$flow.rx.total_pkts]}]
        set avgLatencyLocal [expr {$avgLatencyLocal + \
                          [keylget flow_traffic_status flow.$flow.rx.avg_delay]}]
        set _avgLatency [expr {$_avgLatency + \
                          [keylget flow_traffic_status flow.$flow.rx.avg_delay]}]
        set minLatencyLocal [expr {$minLatencyLocal + \
                          [keylget flow_traffic_status flow.$flow.rx.min_delay]}]
        set _minLatency [expr {$_minLatency + \
                          [keylget flow_traffic_status flow.$flow.rx.min_delay]}]
        set maxLatencyLocal [expr {$maxLatencyLocal + \
                          [keylget flow_traffic_status flow.$flow.rx.max_delay]}]
        set _maxLatency [expr {$_maxLatency + \
                          [keylget flow_traffic_status flow.$flow.rx.max_delay]}]

        if {$debug == 1} {
            ats_log -diag "numPkts - $_numPkts\
                           avgLatency - $_avgLatency\
                           minLatency - $_minLatency\
                           maxLatency - $_maxLatency"
            set _numPkts 0
            set _avgLatency 0
            set _minLatency 0
            set _maxLatency 0
        }
        if {$latency_detail > 0} {
            ats_log -diag "Latency detail enabled @ $latency_detail %"

        foreach rxPort $rxPorts {
            scan $rxPort "%d/%d/%d" ix_c ix_l ix_p
            capture get $ix_c $ix_l $ix_p

            set NOW [clock format [clock seconds] -format {%m%d%y%H%M%S}]
            set file_name "Latency_$latency_detail.$ix_c$ix_l$ix_p$NOW.latency"
            set fd1 [open $file_name "w"]
            puts $fd1 "Per packet latency @ port $ix_c $ix_l $ix_p"
            set flow_results [list                                           \
            "Tx Port"                       tx.port                          \
            "Rx Port"                       rx.port                          \
            "Tx Frames"                     tx.total_pkts                    \
            "Tx Frame Rate"                 tx.total_pkt_rate                \
            "Rx Frames"                     rx.total_pkts                    \
            "Frames Delta"                  rx.loss_pkts                     \
            "Rx Frame Rate"                 rx.total_pkt_rate                \
            "Loss %"                        rx.loss_percent                  \
            "Rx Bytes"                      rx.total_pkts_byte               \
            "Rx Rate (Bps)"                 rx.total_pkt_byte_rate           \
            "Rx Rate (bps)"                 rx.total_pkt_bit_rate            \
            "Rx Rate (Kbps)"                rx.total_pkt_kbit_rate           \
            "Rx Rate (Mbps)"                rx.total_pkt_mbit_rate           \
            "Avg Latency (ns)"              rx.avg_delay                     \
            "Min Latency (ns)"              rx.min_delay                     \
            "Max Latency (ns)"              rx.max_delay                     \
            "First Timestamp"               rx.first_tstamp                  \
            "Last Timestamp"                rx.last_tstamp                   \
            ]
            set flows [keylget flow_traffic_status flow]
            foreach flow [keylkeys flows] {
                set flow_key [keylget flow_traffic_status flow.$flow]
                puts $fd1 "\tFlow $flow"
                foreach {name key} [subst $[subst flow_results]] {
                    puts $fd1 "\t\t$name: \
                          [keylget flow_traffic_status flow.$flow.$key]"
                }
             }

            close $fd1
      }
        }
    }

    set avgLatencyLocal [expr {$avgLatencyLocal/$num_flow}]
    set minLatencyLocal [expr {$minLatencyLocal/$num_flow}]
    set maxLatencyLocal [expr {$maxLatencyLocal/$num_flow}]

    return 1

} ; # End of Proc _get_latency_IxNetwork2

######################################################################
##Procedure Header
# Name:
#    perfUtils::_run_traffic_IxNetwork
#
# Purpose:
#    run the traffic for the run_time seconds
#    and upvars cmd output on IxExplorer
#
# Synopsis:
#    _run_traffic_IxNetwork args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc runs the traffic for the run_time seconds
#    and upvars cmd output on IxExplorer
######################################################################
proc perfUtils::_run_traffic_IxNetwork {cmdOutputs root run_time exec_cmds \
uut tr} {

    upvar $cmdOutputs cmdOutputsLocal
    set traffic $root/traffic

    # Send traffic
    set startTraffic [::ixNet exec start $traffic]

    #Wait for half the test run time
    sleep [expr {$run_time/2.0}]

    #Execute any commands for debug or results
    set cmdOutputsLocal {}
    foreach cmd $exec_cmds {
        lappend cmdOutputsLocal [$uut exec $cmd]
        if { $tr != "" } {
            $tr exec $cmd
        }
        # sleep a while between each show command, 
        # to reduce the impact on resource using
        sleep 3
    }

    #Wait for another half the test run time
    sleep [expr {$run_time/2.0}]

    set stopTraffic [::ixNet exec stop $traffic]

    $uut exec "show platform hardware qfp active statistics drop clear"
     if { $tr != "" } {
        $tr exec "show platform hardware qfp active statistics drop clear"
     }
    sleep 5

    return 1

} ; # End of Proc _run_traffic_IxNetwork

######################################################################
##Procedure Header
# Name:
#   perfUtils::_maxrate
#
# Purpose:
#    return the maxRate on a port
#
# Synopsis:
#    _maxrate args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc returns the maxRate on a port
######################################################################
proc perfUtils::_maxrate {port, stream_id} {
    set maxRate 0; set success 1
    regexp {(\d+)/(\d+)/(\d+)} $port - chas card port
    stream get $chas $card $port 1
    set stream_type [stream cget -frameSizeType]
    if {$stream_type == $::sizeRandom} {
        weightedRandomFramesize get $chas $card $port
	if {[weightedRandomFramesize cget -randomType] == $::randomWeightedPair} {
	    set pairList [weightedRandomFramesize cget -pairList]
	}
	set total_weight 0
	set total_framesize 0
	foreach pair $pairList {
	    set framesize [lindex $pair 0]
            set weight [lindex $pair 1]
	    set total_framesize [mpexpr $total_framesize + $framesize * $weight]
	    set total_weight [mpexpr $total_weight + $weight]
	}
	set frame_size  [mpexpr $total_framesize / $total_weight]
    } else {
	    set frame_size [stream cget -framesize]
    }
    capture get $chas $card $port
    set maxRate [calculateMaxRate $chas $card $port $frame_size]

    set diag "Calculated max_rate - $maxRate"
    ats_results -diag $diag
    ats_log -diag $diag

    return $maxRate
}

######################################################################
##Procedure Header
# Name:
#    perfUtils::_maxrate2
#
# Purpose:
#    return the maxRate on a port using specific stream to calculate
#
# Synopsis:
#    _maxrate2 args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc returns the maxRate on a port using specific stream to calculate
######################################################################
proc perfUtils::_maxrate2 {port stream_id} {
    set maxRate 0; set success 1

    #capture get $chas $card $port
    #set maxRate [calculateMaxRate $chas $card $port $frame_size]
    #set maxRate 320513
    #set maxRate 335121
    #set maxRate $maxrate

    set diag "Calculated max_rate - $maxRate"
    ats_results -diag $diag
    ats_log -diag $diag

    return $maxRate
}

######################################################################
##Procedure Header
# Name:
#    perfUtils::_framesize
#
# Purpose:
#    return the framesize configured on the port
#
# Synopsis:
#    _framesize args
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc returns the framesize configured on the port
######################################################################

proc perfUtils::_framesize {port stream_id} {
    set frameSize 0; set success 1
    regexp {(\d+)/(\d+)/(\d+)} $port - chas card port
    #stream get $chas $card $port 1
    stream get $chas $card $port $stream_id
    set stream_type [stream cget -frameSizeType]
    if {$stream_type == $::sizeRandom} {
	weightedRandomFramesize get $chas $card $port
	if {[weightedRandomFramesize cget -randomType] \
		             == $::randomWeightedPair} {
	    set pairList [weightedRandomFramesize cget -pairList]
	    #puts "weighted pairs:  $pairList"
	}
	set total_weight 0
	set total_framesize 0
        foreach pair $pairList {
            set framesize [lindex $pair 0]
	    set weight [lindex $pair 1]
             set total_framesize [mpexpr $total_framesize + $framesize * $weight]
	     set total_weight [mpexpr $total_weight + $weight]
        }
	set frame_size  [mpexpr $total_framesize / $total_weight]
    } else {
          set frame_size [stream cget -framesize]
    }
    set frameSize $frame_size
    set diag "Calculated frame_size - $frameSize"
    ats_results -diag $diag
    ats_log -diag $diag
    return $frameSize
}

######################################################################
###Procedure Header
## Name:
##    perfUtils::_framesize2
##
## Purpose:
##    return the framesize configured on the port
##
## Synopsis:
##    _framesize2 args
##
## Arguments:
##    too much to be listed
##
## Return Values:
##    1 - Success
##    0 - failure
##
## Description:
##    This Proc returns the framesize configured on the port
#######################################################################

proc perfUtils::_framesize2 {port stream_id} {

    set frameSize 0; set success 1

    regexp {(\d+)/(\d+)/(\d+)} $port - chas card port

    #stream get $chas $card $port 1
    #stream get $chas $card $port $stream_id
    set streamList [interp eval $::ixia::TclInterp " ixNet getL ::ixNet::OBJ-/traffic trafficItem "]
    puts "streamList: $streamList"
    foreach stream $streamList {
	if {[regexp -nocase $stream_id [interp eval $::ixia::TclInterp " ixNet getA ::ixNet::OBJ-/traffic/trafficItem:1 -name"]]} {
		set trafficStream $stream 
	}
    }
    set weightedFrame [interp eval $::ixia::TclInterp " ixNet getA $trafficStream/highLevelStream:1/frameSize -weightedPairs "]
    puts "weightedFrame: $weightedFrame"
    set pairList [interp eval $::ixia::TclInterp " ixNet getA $trafficStream/configElement:0/frameSize -weightedPairs "]    
    puts "pairList: $pairList"
    set total_weight 0
    set total_framesize 0
    for {set i 0} {$i < [llength $pairList]} {incr i +2} {
	set framesize [lindex $pairList $i]
	set weight [lindex $pairList [expr $i+1]]
	set total_framesize [mpexpr $total_framesize + $framesize * $weight]
	set total_weight [mpexpr $total_weight + $weight]
    }
    puts "total_weight: $total_weight"
    puts "total_framesize: $total_framesize"
    set frame_size  [mpexpr $total_framesize / $total_weight]
    set frameSize $frame_size

    set diag "Calculated frame_size - $frameSize"
    ats_results -diag $diag
    ats_log -diag $diag

    return $frameSize
}

######################################################################
##Procedure Header
# Name:
#    perfUtils::_parse_tx_ports
#
# Purpose:
#    parse the tx_port data and upvar the variables
#
# Synopsis:
#    _parse_tx_ports
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc parses the tx_port data and upvar the variables
######################################################################
proc perfUtils::_parse_tx_ports {txPorts txStreamSets txStreams numTxPorts \
returnList tx_ports debug} {

    set success 1; set failure 0
    upvar $txPorts txPortsLocal
    upvar $txStreamSets txStreamSetsLocal
    upvar $txStreams txStreamsLocal
    upvar $numTxPorts numTxPortsLocal
    upvar $returnList returnListLocal

    #Parse Tx ports and all Tx streams
    ###
    if {$debug == 1} {ats_log -diag "tx_ports - $tx_ports"}
    ###
    if {[catch {set portKeys [keylkeys tx_ports]} tclErr]} {
        keylset returnListLocal status $failure
        keylset returnListLocal log [_error 1]
        keylset returnListLocal tclErr $tclErr
        return 0
    }
    set numTxPortsLocal 0
    foreach portKey $portKeys {
        if {[catch { \
             lappend txPortsLocal [keylget tx_ports $portKey.port]} tclErr]} {
             keylset returnListLocal status $failure
             keylset returnListLocal log [_error 1]
             keylset returnListLocal tclErr $tclErr
             return 0
        }
        if {[catch { \
             lappend txStreamSetsLocal [keylget tx_ports $portKey.streams]\
           } tclErr]} {
             keylset returnListLocal status $failure
             keylset returnListLocal log [_error 1]
             keylset returnListLocal tclErr $tclErr
             return 0
        }
        incr numTxPortsLocal
    }
    foreach txStreamSet $txStreamSetsLocal {
        if {$debug == 1} {ats_log -diag "txStreamSet - $txStreamSet"}
        foreach txStream $txStreamSet {
            if {[catch {lappend txStreamsLocal $txStream} tclErr]} {
                keylset returnListLocal status $failure
                keylset returnListLocal log [_error 1]
                keylset returnListLocal tclErr $tclErr
                return 0
             }
        }
    }
    if {$debug == 1} {ats_log -diag "txStreamsLocal - $txStreamsLocal"}

    return 1

} ; # End of proc _parse_tx_ports

######################################################################
##Procedure Header
# Name:
#    perfUtils::_parse_rx_ports
#
# Purpose:
#    parse the rx_port data and upvar the variables
#
# Synopsis:
#    _parse_rx_ports
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc parses the rx_port data and upvar the variables
######################################################################
proc perfUtils::_parse_rx_ports {rxPorts numRxPorts returnList rx_ports debug} {

    set success 1; set failure 0
    upvar $rxPorts rxPortsLocal
    upvar $numRxPorts numRxPortsLocal

    #Parse Rx ports
    if {$debug == 1} {ats_log -diag "rx_ports - $rx_ports"}

    if {[catch {set portKeys [keylkeys rx_ports]} tclErr]} {
        keylset returnListLocal status $failure
        keylset returnListLocal log [_error 2]
        keylset returnListLocal tclErr $tclErr
        return 0
    }

    set numRxPortsLocal 0
    foreach portKey $portKeys {
        if {[catch {lappend rxPortsLocal [keylget rx_ports $portKey.port]} \
            tclErr]} {
            keylset returnListLocal status $failure
            keylset returnListLocal log [_error 2]
            keylset returnListLocal tclErr $tclErr
            return 0
        }
        incr numRxPortsLocal
    }
    return 1

} ; # End of proc _parse_rx_ports

######################################################################
##Procedure Header
# Name:
#    perfUtils::_parse_mtx_ports
#
# Purpose:
#    parse the mtx_port data and upvar the variables
#
# Synopsis:
#    _parse_mtx_ports
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc parses the mtx_port data and upvar the variables
######################################################################
proc perfUtils::_parse_mtx_ports {mtxPorts mtxStreamSets mtxOifSets \
mtxStreams mtxOifs returnList mtx_ports debug} {

    set success 1; set failure 0
    upvar $mtxPorts mtxPortsLocal
    upvar $mtxStreamSets mtxStreamSetsLocal
    upvar $mtxOifSets mtxOifSetsLocal
    upvar $mtxStreams mtxStreamsLocal
    upvar $mtxOifs mtxOifsLocal

    #Parse MTx ports streams and OIF
    if {[info exists mtx_ports]} {
        if {$debug == 1} {ats_log -diag "mtx_ports - $mtx_ports"}

        if {[catch {set portKeys [keylkeys mtx_ports]} tclErr]} {
            keylset returnListLocal status $failure
            keylset returnListLocal log [_error 3]
            keylset returnListLocal tclErr $tclErr
            return $returnList
        }

        foreach portKey $portKeys {
            if {[catch {lappend mtxPortsLocal [keylget \
                mtx_ports $portKey.port]} tclErr]} {
                keylset returnListLocal status $failure
                keylset returnListLocal log [_error 3]
                keylset returnListLocal tclErr $tclErr
                return $returnList
            }
            if {[catch {lappend mtxStreamSetsLocal [keylget mtx_ports \
                $portKey.mcast_streams]} tclErr]} {
                keylset returnListLocal status $failure
                keylset returnListLocal log [_error 3]
                keylset returnListLocal tclErr $tclErr
                return $returnList
            }
            if {[catch {lappend mtxOifSetsLocal [keylget mtx_ports \
                $portKey.mcast_oifs]} tclErr]} {
                keylset returnListLocal status $failure
                keylset returnListLocal log [_error 3]
                keylset returnListLocal tclErr $tclErr
                return $returnList
            }
        }

        foreach mtxStreamSet $mtxStreamSetsLocal {
            foreach mtxStream $mtxStreamSet {
                if {[catch {lappend mtxStreamsLocal $mtxStream} tclErr]} {
                    keylset returnListLocal status $failure
                    keylset returnListLocal log [_error 3]
                    keylset returnListLocal tclErr $tclErr
                    return $returnList
                }
            }
        }

        foreach mtxOifSet $mtxOifSetsLocal {
            foreach mtxOif $mtxOifSet {
                if {[catch {lappend mtxOifsLocal $mtxOif} tclErr]} {
                    #puts $mtxOif
                    keylset returnListLocal status $failure
                    keylset returnListLocal log [_error 3]
                    keylset returnListLocal tclErr $tclErr
                    return $returnList
                }
            }
        }
    }; # End of if

    return 1

} ; # End of proc _parse_mtx_ports


######################################################################
##Procedure Header
# Name:
#    perfUtils::_parse_mrx_ports
#
# Purpose:
#    parse the mrx_port data and upvar the variables
#
# Synopsis:
#    _parse_mrx_ports
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc parses the mrx_port data and upvar the variables
######################################################################
proc perfUtils::_parse_mrx_ports {mrxPorts numMrxPorts returnList mrx_ports \
debug} {

    set success 1; set failure 0
    upvar $mrxPorts mrxPortsLocal
    upvar $numMrxPorts numMrxPortsLocal
    #Parse Rx ports
    if {$debug == 1} {ats_log -diag "mrx_ports - $mrx_ports"}

    if {[catch {set portKeys [keylkeys mrx_ports]} tclErr]} {
        keylset returnListLocal status $failure
        keylset returnListLocal log [_error 2]
        keylset returnListLocal tclErr $tclErr
        return 0
    }

    set numMrxPortsLocal 0
    foreach portKey $portKeys {
        if {[catch {lappend mrxPortsLocal [keylget mrx_ports $portKey.port]} \
           tclErr]} {
            keylset returnListLocal status $failure
            keylset returnListLocal log [_error 2]
            keylset returnListLocal tclErr $tclErr
            return 0
        }
        incr numMrxPortsLocal
    }
    return 1

} ; # End of proc _parse_mrx_ports

######################################################################
##Procedure Header
# Name:
#    perfUtils::_error
#
# Purpose:
#    define the errors and returns respective error msg
#
# Synopsis:
#    _parse_rx_ports
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc defines the errors and returns respective error msg
######################################################################
proc perfUtils::_error {id} {

    set success 1

    #Define error messages
    set err(1) "ERROR-1: incorrect tx_port format. Expecting keyed list e.g.\
                    {port1 {{port 1/6/1} {streams {3 4 1}}}}\
                    {port2 {{port 1/12/1} {streams {23 2 24 25}}}}"
    set err(2) "ERROR-2: incorrect rx_port format. Expecting keyed list e.g. \
                    {port1 {{port 1/6/1}}} {port2 {{port 1/12/1}}}"
    set err(3) "ERROR-3: incorrect mtx_port format. Expecting keyed list e.g. \
                    {port2 {{port 1/12/1} {mcast_streams {24 25}}\
                    {mcast_oifs {100 100}}}}"
    set err(4) "ERROR (findNdr argument): -max_rate must be a positive value \
                      greater than 1"
    set err(5) "ERROR (findNdr argument): -min_rate must be a positive value"
    set err(6) "ERROR (findNdr argument): -threshold must be a positive value"
    set err(7) "ERROR (findNdr argument): -uds must be either uds1 or uds2"
    set err(8) "ERROR (findNdr): Check your capture buffer filter"
    set err(9) "ERROR (findNdr argument): -tx_mode must be \
                                          either packet or advanced"
    set err(10) "ERROR (findNdr): Check your port_rx_mode, should be \
                                  capture_and_measure with IxNetwork"

    return $err($id)

} ; # End of proc _error

####################################################
# Description
####################################################
procDescr perfUtils::parseNdrResults {
    Description:
    Usage:
    Example:
    Arguments:
    Return Value:
}

#######################################################
#This proc finds the NDR and returns NDR along with latencies and other stats
#######################################################
proc perfUtils::parseNdrResults {args} {

    #mandatory args
    set man_args {
        -result                 ANY
    }

    #optional_args
    set opt_args {
        -dashboard                CHOICES 0 1
                                  DEFAULT 0
    }

    #Parse the dashed arguments
    parse_dashed_args -args $args \
                      -mandatory_args $man_args -optional_args $opt_args

    #Initialize variables
    set ndr_mpps 0
    set avg_ndr_latency 0
    set avg_cust_latency 0
    set avg_95_latency 0
    set avg_75_latency 0
    set avg_50_latency 0
    set frame_size 0
    set test_run_time 0
    set cpp_util 0
    set cpp_mem 0
    set fp_util 0
    set fp_mem 0; set fp_mem_value 0; set fp_mem_perc_value 0
    set rp_util 0; set rp_mem_value 0; set rp_mem_perc_value 0
    set rp_mem 0
    set cmdOutputs [keylget result cmd_outputs]
    set numPkts [keylget result num_pkts]
    set frame_size [keylget result frame_size]
    if { [catch {
        set ndr_mpps [mpexpr [keylget result ndr]/1000000.00]
        set ndr_bps [mpexpr [keylget result ndr] * $frame_size * 8.0]
        set ndr_gbps [mpexpr $ndr_bps/1000000000.00] 
    } errmsg ] } {
        set ndr_mpps 0
        set ndr_bps 0
        set ndr_gbps 0
        ats_log -diag "parseNdrResults: failed to get NDR"
    }


    if {$numPkts >= 0} {
        catch {
            set avg_ndr_latency [expr {[keylget result latency(NDR)]/1000.00}]
            set avg_cust_latency [expr {[keylget result latency(CUST)]/1000.00}]
            #set avg_ndr_latency [expr {[keylget result latency(100)]/1000.00}]
            set avg_95_latency [expr {[keylget result latency(95)]/1000.00}]
            set avg_75_latency [expr {[keylget result latency(75)]/1000.00}]
            set avg_50_latency [expr {[keylget result latency(50)]/1000.00}]
       }
    }
    if {[catch {
        set test_run_time [keylget result run_time]
        if {$cmdOutputs != ""} {
            set cpp_util [parseCppUtil $cmdOutputs]
            set cpp_mem [parseCppMem $cmdOutputs]
            set rp_util [parseRpUtil $cmdOutputs]
            set rp_mem [parseRpMem $cmdOutputs]
            set fp_util [parseFpUtil $cmdOutputs]
            set fp_mem [parseFpMem $cmdOutputs]

            regexp -nocase "(\[0-9\]+)\[ \]+\\(\[ \]*\[0-9\]+%\\)" $fp_mem \
                           dummy fp_mem_value
            regexp -nocase "\[0-9\]+\[ \]+\\(\[ \]*(\[0-9\]+)%\\)" $fp_mem \
                           dummy fp_mem_perc_value
            regexp -nocase "(\[0-9\]+)\[ \]+\\(\[ \]*\[0-9\]+%\\)" $rp_mem \
                           dummy rp_mem_value
            regexp -nocase "\[0-9\]+\[ \]+\\(\[ \]*(\[0-9\]+)%\\)" $rp_mem \
                           dummy rp_mem_perc_value
        }
    } errmsg] } {
        ats_log -info "parseNdrResults catch errmsg:$errmsg"
    }

    if {$dashboard == 0} {
        set parsedResults "===>> NDR - $ndr_mpps  Mpps | NDR - $ndr_gbps Gbps \
       | Latency@NDR - $avg_ndr_latency us | Latency@95% - $avg_95_latency us \
       | Latency@75% - $avg_75_latency us | Latency@50% - $avg_50_latency us \
       | Latency@CUST - $avg_cust_latency us \
       | Frame Size - $frame_size bytes | Runtime - $test_run_time ms \
       | CPP CPU Utilization $cpp_util % | CPP Memory Utilization $cpp_mem B \
       | FP CPU Utilization $fp_util % | FP Memory Utilization $fp_mem kB \
       | RP CPU Utilization $rp_util % | RP Memory Utilization $rp_mem kB <<==="
        return $parsedResults
    } else {
        #NDR
        keylset perfvalues $frame_size.measure1.name NDR
        keylset perfvalues $frame_size.measure1.order 1
        keylset perfvalues $frame_size.measure1.desc N/A
        keylset perfvalues $frame_size.measure1.unit Mpps
        keylset perfvalues $frame_size.measure1.value $ndr_mpps
        keylset perfvalues $frame_size.measure1.perc_value "N/A"
        #NDR
        keylset perfvalues $frame_size.measure12.name NDR
        keylset perfvalues $frame_size.measure12.order 1
        keylset perfvalues $frame_size.measure12.desc N/A
        keylset perfvalues $frame_size.measure12.unit Gbps
        keylset perfvalues $frame_size.measure12.value $ndr_gbps
        keylset perfvalues $frame_size.measure12.perc_value "N/A"
        if {$numPkts >= 0} {
            #Latency@NDR
            keylset perfvalues $frame_size.measure2.name Latency@NDR
            keylset perfvalues $frame_size.measure2.order 1
            keylset perfvalues $frame_size.measure2.desc N/A
            keylset perfvalues $frame_size.measure2.unit us
            keylset perfvalues $frame_size.measure2.value $avg_ndr_latency
            keylset perfvalues $frame_size.measure2.perc_value "N/A"
            #Latency@CUST
            keylset perfvalues $frame_size.measure22.name Latency@CUST
            keylset perfvalues $frame_size.measure22.order 1
            keylset perfvalues $frame_size.measure22.desc N/A
            keylset perfvalues $frame_size.measure22.unit us
            keylset perfvalues $frame_size.measure22.value $avg_cust_latency
            keylset perfvalues $frame_size.measure22.perc_value "N/A"
            #Latency@95%
            keylset perfvalues $frame_size.measure3.name Latency@95%
            keylset perfvalues $frame_size.measure3.order 1
            keylset perfvalues $frame_size.measure3.desc N/A
            keylset perfvalues $frame_size.measure3.unit us
            keylset perfvalues $frame_size.measure3.value $avg_95_latency
            keylset perfvalues $frame_size.measure3.perc_value "N/A"
            #Latency@75%
            keylset perfvalues $frame_size.measure4.name Latency@75%
            keylset perfvalues $frame_size.measure4.order 1
            keylset perfvalues $frame_size.measure4.desc N/A
            keylset perfvalues $frame_size.measure4.unit us
            keylset perfvalues $frame_size.measure4.value $avg_75_latency
            keylset perfvalues $frame_size.measure4.perc_value "N/A"
            #Latency@50%
            keylset perfvalues $frame_size.measure5.name Latency@50%
            keylset perfvalues $frame_size.measure5.order 1
            keylset perfvalues $frame_size.measure5.desc N/A
            keylset perfvalues $frame_size.measure5.unit us
            keylset perfvalues $frame_size.measure5.value $avg_50_latency
            keylset perfvalues $frame_size.measure5.perc_value "N/A"
        }
        #CPP Utilization
        keylset perfvalues $frame_size.measure6.name "QFP Utilization"
        keylset perfvalues $frame_size.measure6.order 1
        keylset perfvalues $frame_size.measure6.desc N/A
        keylset perfvalues $frame_size.measure6.unit "%"
        keylset perfvalues $frame_size.measure6.value $cpp_util
        keylset perfvalues $frame_size.measure6.perc_value "N/A"
        #CPP Memory
        keylset perfvalues $frame_size.measure7.name "QFP Memory"
        keylset perfvalues $frame_size.measure7.order 1
        keylset perfvalues $frame_size.measure7.desc N/A
        keylset perfvalues $frame_size.measure7.unit B
        keylset perfvalues $frame_size.measure7.value $cpp_mem
        keylset perfvalues $frame_size.measure7.perc_value "N/A"
        #FP Utilization
        keylset perfvalues $frame_size.measure8.name "ESP Utilization"
        keylset perfvalues $frame_size.measure8.order 1
        keylset perfvalues $frame_size.measure8.desc N/A
        keylset perfvalues $frame_size.measure8.unit "%"
        keylset perfvalues $frame_size.measure8.value $fp_util
        keylset perfvalues $frame_size.measure8.perc_value "N/A"
        #FP Memory
        keylset perfvalues $frame_size.measure9.name "ESP Memory"
        keylset perfvalues $frame_size.measure9.order 1
        keylset perfvalues $frame_size.measure9.desc N/A
        keylset perfvalues $frame_size.measure9.unit "kB"
        keylset perfvalues $frame_size.measure9.value $fp_mem_value
        keylset perfvalues $frame_size.measure9.perc_value $fp_mem_perc_value
        #RP Utilization
        keylset perfvalues $frame_size.measure10.name "RP Utilization"
        keylset perfvalues $frame_size.measure10.order 1
        keylset perfvalues $frame_size.measure10.desc N/A
        keylset perfvalues $frame_size.measure10.unit "%"
        keylset perfvalues $frame_size.measure10.value $rp_util
        keylset perfvalues $frame_size.measure10.perc_value "N/A"
        #RP Memory
        keylset perfvalues $frame_size.measure11.name "RP Memory"
        keylset perfvalues $frame_size.measure11.order 1
        keylset perfvalues $frame_size.measure11.desc N/A
        keylset perfvalues $frame_size.measure11.unit "kB"
        keylset perfvalues $frame_size.measure11.value $rp_mem_value
        keylset perfvalues $frame_size.measure11.perc_value $rp_mem_perc_value

        return $perfvalues
    }

} ; # End of parseNdrResults

####################################################
# Description
####################################################
procDescr perfUtils::writePerfValues {
    Description:
    Usage:
    Example:
    Arguments:
    Return Value:
}

proc perfUtils::writePerfValues {args} {

    set man_args {
             -uut ANY
             -image_type ANY
             -protocol ANY
             -file_name ANY
             -keylist ANY
             -packet_sizes ANY
             -profile ANY
             -functional_area ANY
             -feature ANY
             -feature_order ANY
             -scale_size ANY
             -a_flag ANY
    }

    set opt_args {
             -feat_comments ANY
                            DEFAULT         N/A
             -cat_name      ANY
                            DEFAULT         N/A
             -tid           ANY
                            DEFAULT         N/A
             -cid           ANY
                            DEFAULT         N/A
             -image_branch  ANY
                            DEFAULT         IMAGE_BRANCH
             -image_name    ANY
                            DEFAULT         RLS
    }

    parse_dashed_args -args $args -mandatory_args $man_args \
                      -optional_args $opt_args -return_direct

    if {$image_type == "BiWeekly"} {
        set image_name [getImageName $uut]
        set image_name "$image_name\($image_branch\)"
    } else {
        #set image_name $rls_name
        set image_name [getImageName $uut]
        set image_name "$image_name\($image_branch\)"
    }
    set image_date [getImageDate $uut]
    set run_date [clock format [clock seconds] -format {%m-%d-%y}]
    set hardware [getHardware $uut]

    if {$a_flag} {
        set fd1 [open $file_name "a+"]
    } else {
        set fd1 [open $file_name "w"]
        set content "ASR,Hardware,FunctionalArea,Profile,Feature,"
        append content "Feature_Comments,Feature_Order,Protocol,ImageName,"
        append content "ImageDate,ImageType,PacketSize,ScaleSize,CategoryName,"
        append content "MeasureName,Measure_Order,MeasureDesc,MeasureUnit,"
        append content "MeasureValue,PercentageValue,TopologyFileID,"
        append content "ConfigurationFileID"
        puts $fd1 "$content"
    }
    #$feat_comments
    foreach pkt $packet_sizes {
    # Get the measure keyes like measure1,measure2... etc. for the packet size
        set keys [keylkeys keylist $pkt]
        foreach key $keys {
            set content "ASR1K,$hardware,$functional_area,$profile,"
            append content "$feature,$feat_comments,$feature_order,"
            append content "$protocol,$image_name,$image_date,$image_type,"
            append content "$pkt Bytes,$scale_size,$cat_name,"
            append content "[keylget keylist $pkt.$key.name],"
            append content "[keylget keylist $pkt.$key.order],"
            append content "[keylget keylist $pkt.$key.desc],"
            append content "[keylget keylist $pkt.$key.unit],"
            append content "[keylget keylist $pkt.$key.value],"
            append content "[keylget keylist $pkt.$key.perc_value],$tid,$cid"
            puts $fd1 "$content"
            aetest::action -diag "$content"
        } ; # end of foreach_keys_loop
    } ;# End of forach_pkt_loop
    close $fd1
}


####################################################
# Description
####################################################
procDescr perfUtils::writeMyPerfValues {
    Description:
    Usage:
    Example:
    Arguments:
    Return Value:
}

proc perfUtils::writeMyPerfValues {args} {

    set man_args {
             -uut ANY
             -file_name ANY
             -keylist ANY
             -packet_sizes ANY
             -feature ANY
             -profile ANY
             -scale_size ANY
             -a_flag ANY
    }

    set opt_args {
           -profile2   ANY
                       DEFAULT         N/A
           -extra_data ANY
                       DEFAULT ""
    }

    parse_dashed_args -args $args -mandatory_args $man_args \
                      -optional_args $opt_args -return_direct

    set image_date [getImageDate $uut]
    set image_branch [getImageBranch $uut]
    set run_date [clock format [clock seconds] -format {%m-%d-%y}]
    set hardware [getHardware $uut]

    if {$a_flag} {
        set fd1 [open $file_name "a+"]
    } else {
        set fd1 [open $file_name "w"]
    }
    #$feat_comments
    foreach pkt $packet_sizes {
    # Get the measure keyes like measure1,measure2... etc. for the packet size
        set keys [keylkeys keylist $pkt]
        set rp_util 0
        set rp_mem 0
        set fp_util 0
        set fp_mem 0
        set qfp_util 0
        set qfp_mem 0
        set Mpps 0
        set Gbps 0
        set Latency 0
        catch {
            set rp_util [keylget keylist $pkt.measure10.value]
            set rp_mem [keylget keylist $pkt.measure11.value]
            set fp_util [keylget keylist $pkt.measure8.value]
            set fp_mem [keylget keylist $pkt.measure9.value]
            set qfp_util [keylget keylist $pkt.measure6.value]
            set qfp_mem [keylget keylist $pkt.measure7.value]
            set Mpps [keylget keylist $pkt.measure1.value]
            set Gbps [keylget keylist $pkt.measure12.value]
            #set Latency [keylget keylist $pkt.measure3.value]
            set Latency [keylget keylist $pkt.measure22.value]
        }
        if {$extra_data == "" } {
            puts $fd1 "exec_date,$run_date,hardware,$hardware,image_branch,\
                $image_branch,image_date,$image_date,scale_size,$scale_size,\
                rp_util,$rp_util,fp_util,$fp_util,qfp_util,$qfp_util,rp_mem,\
              $rp_mem,fp_mem,$fp_mem,qfp_mem,$qfp_mem,Mpps,$Mpps,Gbps,$Gbps,\
                Latency,$Latency,packet_size,$pkt,feature,$feature,profile1,\
                        $profile,profile2,$profile2"
        } else {
            puts $fd1 "exec_date,$run_date,hardware,$hardware,image_branch,\
               $image_branch,image_date,$image_date,scale_size,$scale_size,\
               rp_util,$rp_util,fp_util,$fp_util,qfp_util,$qfp_util,rp_mem,\
             $rp_mem,fp_mem,$fp_mem,qfp_mem,$qfp_mem,Mpps,$Mpps,Gbps,$Gbps,\
               Latency,$Latency,packet_size,$pkt,feature,$feature,profile1,\
                       $profile,profile2,$profile2,$extra_data"
        }

    } ;# End of forach_pkt_l
    close $fd1
}

######################################################################
##Procedure Header
# Name:
#    perfUtils::generate_keyed_result
#
# Purpose:
#    generate keyed result
#
# Synopsis:
#    generate_keyed_result
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc generates keyed result
######################################################################
proc perfUtils::generate_keyed_result {args} {

    set man_args {
             -uut            ANY
             -tx_ports       ANY
             -pps            ANY
             -frame_size     ANY
    }
    set opt_args {

    }
    set ret {}
    parse_dashed_args -args $args -mandatory_args $man_args \
                      -optional_args $opt_args -return_direct

    set portKeys [keylkeys tx_ports]
    set port_list ""
    set stream_list ""
    foreach portKey $portKeys {
        lappend port_list [keylget tx_ports $portKey.port]
        lappend stream_list [keylget tx_ports $portKey.streams]
    }

    set result [ixia::traffic_control -port_handle $port_list -action stop]
    ats_log -info "ixia stop traffic: $result"
    foreach handle $port_list streams $stream_list {
        foreach stream $streams {
             set traffic_status [ixia::traffic_config \
                     -port_handle $handle \
                     -mode modify \
                     -stream_id $stream \
                     -rate_pps $pps \
                     -frame_size $frame_size ]
             ats_log -info "modify $handle stream: $traffic_status"
             if {[keylget traffic_status status] == 0 } {
                 aetest::action -diag "modify traffic failed:$traffic_status"
                 return $ret
             }
        }
    }
    set traffic_status [ixia::traffic_control -port_handle $port_list \
                        -action run]
    ats_log -info "start ixia traffic: $traffic_status"
    if {[keylget traffic_status status] == 0 } {
        aetest::action -diag "start traffic failed:$traffic_status"
        return $ret
    }

    sleep 60
    ats_log -info "collect the asr1k cpu and memory data"
    set exec_cmds ""
    lappend exec_cmds "show platform hardware qfp active data util"
    lappend exec_cmds "show platform hardware qfp active infrastructure exmem \
                       statistics"
    lappend exec_cmds "show platform software status control-processor brief"
    set cmdOutputsLocal {}
    foreach cmd $exec_cmds {
         lappend cmdOutputsLocal [$uut exec $cmd]
        # sleep a while between each show command, 
        # to reduce the impact on resource using
         sleep 3
    }
    sleep 10
    set result [ixia::traffic_control -port_handle $port_list -action stop]
    ats_log -info "ixia stop traffic: $result"

    keylset output status 1
    keylset output ndr $pps
    keylset output num_pkts 0
    keylset output latency(NDR) 0
    keylset output min_latency 0
    keylset output max_latency 0
    keylset output cmd_outputs $cmdOutputsLocal
    keylset output run_time 60
    keylset output frame_size $frame_size

    set ret [perfUtils::parseNdrResults -result $output -dashboard 1]
    return $ret
}

######################################################################
##Procedure Header
# Name:
#    perfUtils::calculate_latency
#
# Purpose:
#    calculate latency value
#
# Synopsis:
#    calculate_latency
#
# Arguments:
#    too much to be listed
#
# Return Values:
#    1 - Success
#    0 - failure
#
# Description:
#    This Proc calculates latency value
######################################################################
proc perfUtils::calculate_latency {args} {

    set man_args {
             -tx_ports       ANY
             -rx_ports       ANY
             -ndr            ANY
             -frame_size     ANY
    }
    set opt_args {
            -uds            ANY
                            default uds1
    }
    ats_log -info "start to calculate_latency"
    set ret {}
    keylset ret status 0
    parse_dashed_args -args $args -mandatory_args $man_args \
                      -optional_args $opt_args -return_direct

    set portKeys [keylkeys tx_ports]
    set tx_port_list ""
    set tx_stream_list ""
    foreach portKey $portKeys {
        lappend tx_port_list [keylget tx_ports $portKey.port]
        lappend tx_stream_list [keylget tx_ports $portKey.streams]
    }

    set portKeys [keylkeys tx_ports]
    set rx_port_list ""
    set rx_stream_list ""
    foreach portKey $portKeys {
        lappend rx_port_list [keylget rx_ports $portKey.port]
        lappend rx_stream_list [keylget rx_ports $portKey.streams]
    }

    set result [ixia::traffic_control -port_handle $tx_port_list -action stop]
    ats_log -info "ixia stop traffic: $result"
    foreach handle $tx_port_list streams $tx_stream_list {
        foreach stream $streams {
            set traffic_status [ixia::traffic_config -port_handle $port \
                -mode modify \
                -stream_id $stream \
                -rate_pps [expr {$pps/2}] \
            ]
            ats_log -info "modify $handle stream: $traffic_status"
            if {[keylget traffic_status status] == 0 } {
                aetest::action -diag "modify traffic failed:$traffic_status"
                keylset ret log "modify traffic failed:$traffic_status"
                return $ret
            }
        }
    }


    ixia::interface_config -port_handle $rx_port_list \
           -port_rx_mode capture

    ixia::traffic_control -port_handle $tx_port_list -action clear_stats
    ixia::traffic_control -port_handle $rx_port_list -action clear_stats

    ats_log -info "config packet buffer"
    ixia::packet_control -port_handle $rx_port_list -action stop
    set result [ixia::packet_config_buffers -port_handle $rx_port_list \
     -slice_size 100 -capture_mode continuous -continuous_filter filter]
    ats_log -info "result is $result"

    ats_log -info "start packet capture"
    set result [ixia::packet_control -port_handle $rx_port_list -action start]
    ats_log -info "start packet_control:$result"

    set tr_stat [ixia::traffic_control -action run \
         -duration 30 -port_handle $tx_port_list]

    if {[keylget tr_stat status] == 0} {
        aetest::action -diag "Ixia up Traffic start failed:$tr_stat"
        keylset ret log "Ixia up Traffic start failed:$tr_stat"
        return $ret
    }

    sleep 30
    set result [ixia::packet_control -port_handle $tx_port_list -action stop]

    sleep 3
    #stop the packet capture
    ats_log -info "stop packet capture"
    set result [ixia::packet_control -port_handle $rx_port_list -action stop]
    ats_log -info "stop packet_control:$result"

    get the Rx packet stats (Capture Buffer), enable capture on the Rx port
    set rx_pkt_stats [ixia::packet_stats -port_handle $rx_port_list \
                 -chunk_size 8000000]

    if {[keylget rx_pkt_stats status] != $SUCCESS} {
        set diag "Couldn't get RX packet stats on $rx_port_list"
        ats_results -diag $diag
        keylset ret log $diag
        return $ret
    }

    set count [llength rx_port_list]
    set numPkts 0
    set max_latency 0
    set min_latency 0
    set avg_latency 0
    foreach port $rx_port_list {
        set numPkts [expr {$numPkts+\
            [keylget rx_pkt_stats $port.aggregate.num_frames]}]
        set max_latency [expr {$max_latency+\
            [keylget rx_pkt_stats $port.aggregate.max_latency]}]
        set min_latency [expr {$min_latency+\
            [keylget rx_pkt_stats $port.aggregate.min_latency]}]
        set avg_latency [expr {$avg_latency+\
            [keylget rx_pkt_stats $port.aggregate.average_latency]}]
     }
     keylset ret status 1 numPkts $numPkts \
        max_latency [expr {$max_latency/$count}] \
        min_latency [expr {$min_latency/$count}] \
        avg_latency [expr {$avg_latency/$count}]

     return $ret
}

########################## STANDARD SCRIPT FOOTER  ###########################
# $Log: perfUtils.tcl,v $
# Revision 1.9  2019/02/07 14:03:03  kkg
# add control on ARP/ND via environment variable when using Spirent STC
#
# Revision 1.8  2017/10/31 18:26:44  kkg
# change cpp to qfp references due to the hidden CLi removal
#
# Revision 1.7  2015/05/06 02:15:36  rupan
# modify according to CSCut92600: (1) main logic enhancement; (2) latency
# hardcode issue
#
# Revision 1.6  2015/04/09 20:03:00  kkg
# fixed typo in catch
#
# Revision 1.5  2015/04/02 17:40:46  kkg
# fixed a syntax error in parseNDR
#
# Revision 1.4  2015/02/11 21:29:23  kkg
# Currently parseNdrResults will error out and abort a test when ndr is not found.Adding a catch to protect it from happening...
#
# Revision 1.3  2014/11/03 07:20:15  rupan
# set mtxPkts float rather than original int in order to avoid out-of-bound
# issue
#
# Revision 1.2  2014/09/26 08:13:34  rupan
# add -tr param to support show info on other routers besides uut; modify
# remove undefined variable "rls_name" in writePerfValues proc
#
# Used for emacs
# Local Variables:
# mode:tcl
# indent-tabs-mode:nil
# End:

