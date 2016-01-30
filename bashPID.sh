#!/bin/bash
#A PID fan controller
#Depenencies: bash, GNU bc
#Matt Cooper, 2015
# TODO: config file, generic sensor/cdev
# -The initialisation part looks like it would
#  be better off in a .conf
#
# - ACPI and cpufreq throttling look like they
#   can be implemented here in the same fashion
#
# - Would precision timing be better? Code
#   assumes that calculation time is negligible,
#   could use date time to give system time in ns
#   and put that as dt in calcs
#
#DESIRED: online tuning and autotune
################initialisation:

dt=1        # Time base
p1=0.025       # unit is pwm/millidegree
p2=0.025
i1=0.0025      # pwm seconds per millidegree
i2=0.0025
d1=0.0000025
d2=0.0000025
s1=25000
s2=15000 # Set point (millidegrees)
#pwm_min1=110 #these are global values
pwm_max1=255 #used for broken loop, best to leave at max
pwm1_mintrip=22500
pwm_min1_1=100 #pwm when below this point
pwm1_maxtrip=27500
pwm_max1_1=255 #pwm when over this point
pwm_min2=0
pwm_max2=255
pwm2_mintrip=10000
pwm_min2_1=0
pwm2_maxtrip=20000
pwm_max2_1=255
half=0.5
C1=0       # controller bias values (Integration constants)
C2=25       #
I1max=255    # Max value of integrator 1
I1min=110    # Min value of integrator 1
I1init=110    # initial value of integrator 1
I2max=180    # Max value of integrator 2
I2min=-20   # Min value of integrator 2
I2init=100    # initial value of integator 2
Tmax=30000        #Max temperature, disable pwms (or whatever to get full fanspeed/cooling), sleep
#Tmaxcmd     #additional command to run when Tmax reched
Tmaxhyst=20000    #Hysteresis value for Tmax. Script starts from beginning once reached
#Tmaxhystcmd #additional command to run when Tmaxhyst reached
SuperIo=/sys/devices/platform/it87.552           #store SuperIo path to make it easier to read and write for devices
pwm1path=$SuperIo/pwm1
pwm1en=$SuperIo/pwm1_enable
pwm2path=$SuperIo/pwm3
pwm2en=$SuperIo/pwm3_enable
fan=$SuperIo/fan1_input
temp1=/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon*/temp1_input
###########################
gov_restart=conservative
gov_throttle=powersave
f0=4000000
t0=30000
f1=3600000
t1=32000
f2=3400000
t2=34000
f3=2800000
t3=36000
f4=2100000
t4=38000
f5=1400000
t5=40000
######################################################################
for z in {0..7}
do cpufreq-set -c $z -g $gov_restart -u 4000000
done
echo 1 > $pwm1en &           #enable pwm
echo 1 > $pwm2en &           #enable pwm
wait

#echo 255 > $pwm1path &                             #set initial pwm here
#echo 255 > $pwm2path &                             #set initial pwm here
#sleep 5                                            #use if you want a running start
pwm_old1=$(cat $pwm1path)                           #setup pwm_old
pwm_old2=$(cat $pwm2path)                           #setup pwm_old
pwm_raw1=$pwm_old1                                  #setup raw pwm
pwm_raw2=$pwm_old2
##set up old temps - only needed for weighted average derivative
T5=$(cat $temp1)
#E5=$(($T5 - $s1))
#sleep $dt
T4=$(cat $temp1)
#E4=$(($T4 - $s1))
#sleep $dt
T3=$(cat $temp1)
#E3=$(($T3 - $s1))
#sleep $dt
T2=$(cat $temp1)
#E2=$(($T2 - $s1))
#sleep $dt
T1=$(cat $temp1)
#E1=$(($T1 - $s1))
#sleep $dt
T0=$(cat $temp1)
#E0=$(($T0 - $s1))

O1=$C1
O2=$C2
I1=$I1init
I2=$I2init
##begin main loop

while [ $T0 -lt $Tmax ] #break loop when T>Tmax
       do {
          T5=$T4
          T4=$T3
          T3=$T2
          T2=$T1
          T1=$T0

#########
sleep $dt
#########
       T0=$(cat $temp1)
##temp functions now stored
##################################console output for user
clear
date
echo s1 = $s1 s2 = $s2
echo pwm1 $(cat $pwm1path)
echo pwm2 $(cat $pwm2path)
echo Fan Speed = $(cat $SuperIo/fan1_input) 
echo pwm_raw1 = $pwm_raw1 pwm_raw2 = $pwm_raw2
echo P1 = $P1, P2 = $P2, I1 = $I1, I2 = $I2, D1 = $D1, D2 = $D2
echo O1 = $O1 O2 = $O2
echo T5 = $T5 T4 = $T4 T3 = $T3 T2 = $T2 T1 = $T1 T0 = $T0
echo E5 = $E5 E4 = $E4 E3 = $E3 E2 = $E2 E1 = $E1 E0 = $E0
echo pwm_new1 = $pwm_new1 pwm_new2 = $pwm_new2
##################################################


###########PID part-do for both sets of constants
###################pwm1######################
if [ $T0 -gt $pwm1_maxtrip ]
 then
 pwm_new1=$pwm_max1_1
 pwm_raw1=$pwm_max1_1
 I1=$I1max
 elif [ $T0 -lt $pwm1_mintrip ]
 then
 pwm_new1=$pwm_min1_1
 pwm_raw1=$pwm_min1_1
 else

{
          E5=$(($T5 - $s1))
          E4=$(($T4 - $s1))
          E3=$(($T3 - $s1))
          E2=$(($T2 - $s1))
          E1=$(($T1 - $s1))
          E0=$(($T0 - $s1))
#Integral - trapezium rule with min/max values
I1=$(echo "(($i1 * $dt * $half * ($E0 + $E1)) + $I1 )" | bc -l)
I1int=$(echo "($I1 + 0.5)/1" | bc)               #now an integer
if [ $I1int -gt $I1max ]
  then
  I1=$I1max
  elif [ $I1int -lt $I1min ]
  then
  I1=$I1min
  else
  :
fi

#(derivative- use simple definition)
#D= d * (err_last - err_now) / dt
#simple derivative
#D1=$(echo "$d1 *  $(($E0 - $E1)) / $dt" | bc -l)
#weighted average
D1=$(echo "$d1 *  (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)
# Proportional term
P1=$(echo "$p1 * $E0" | bc -l)
O1=$(echo "$P1 + $I1 + $D1" | bc -l)
pwm_raw1=$(echo "$C1 + $O1" | bc -l) # add the constants in
pwm_new1=$(echo "($pwm_raw1 + 0.5)/1" | bc) #now an integer
if [ $pwm_new1 -gt $pwm_max1_1 ]
 then
 pwm_new1=$pwm_max1_1
 pwm_raw1=$pwm_max1_1
 elif [ $pwm_new1 -lt $pwm_min1_1 ]
 then
 pwm_new1=$pwm_min1_1
 pwm_raw1=$pwm_min1_1
 else
:
fi
pwm_old1=$(echo "($pwm_raw1 + $O1 + 0.5)/1" | bc) #need to call from these raw values
 }
fi
echo $pwm_new1 > $pwm1path &          #these lines do the fanspeed
########################end of pwm1################
##############################pwm2#################
if [ $T0 -gt $pwm2_maxtrip ]
 then
 pwm_new2=$pwm_max2_1
 pwm_raw2=$pwm_max2_1
 I2=$I2max
 elif [ $T0 -lt $pwm2_mintrip ]
 then
 pwm_new2=$pwm_min2_1
 pwm_raw2=$pwm_min2_1
 else

{
          E5=$(($T5 - $s2))
          E4=$(($T4 - $s2))
          E3=$(($T3 - $s2))
          E2=$(($T2 - $s2))
          E1=$(($T1 - $s2))
          E0=$(($T0 - $s2))
I2=$(echo "(($i2 * $dt * $half * ($E0 + $E1)) + $I2 )" | bc -l)
I2int=$(echo "($I2 + 0.5)/1" | bc)
if [ $I2int -gt $I2max ]
 then
 I2=$I2max
 elif [ $I2int -lt $I2min ]
 then
 I2=$I2min
 else
:
fi
#D2=$(echo "$d2 *  $(($E0 - $E1)) / $dt" | bc -l)
D2=$(echo "$d2 *  (($(($E0 - $E1)) / $dt) + $(($E0 - $E2)) / (4 * $dt) + $(($E0 - $E3)) / (6 * $dt) + $(($E0 - $E4)) / (8 * $dt) + $(($E0 - $E5)) / (10 * $dt))" | bc -l)
P2=$(echo "$p2 * $E0" | bc -l)
#output O=P+I+D
O2=$(echo "$P2 + $I2 + $D2" | bc -l)
pwm_raw2=$(echo "$C2 + $O2" | bc -l) #
pwm_new2=$(echo "($pwm_raw2 + 0.5)/1" | bc)
if [ $pwm_new2 -gt $pwm_max2_1 ]
 then
 pwm_new2=$pwm_max2_1
 pwm_raw2=$pwm_max2_1
 elif [ $pwm_new2 -lt $pwm_min2_1 ]
 then
 pwm_new2=$pwm_min2_1
 pwm_raw2=$pwm_min2_1
 else
:
fi
pwm_old2=$(echo "($pwm_raw2 + $O2 + 0.5)/1" | bc)
 }
fi
echo $pwm_new2 > $pwm2path &           #change. be careful.
################################end of pwm2##################
#########frequency scaler#####
      
    if [ $T0 -gt $t5 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f5
        done
         }
    elif [ $T0 -gt $t4 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f4
           done
            }
     elif [ $T0 -gt $t3 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f3
           done
            }
    elif [ $T0 -gt $t2 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f2
           done
            }
    elif [ $T0 -gt $t1 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f1
           done
            }
    elif [ $T0 -lt $t1 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f0
           done
            }
        fi 
#############end of frequency scaler
 }
done

#loop broken for cooling and reinitialisation

echo Too hot, fans on max
#for z in {0..7}
#do cpufreq-set -c $z -g $gov_throttle
#done
echo $pwm_max1 > $pwm1path &
echo $pwm_max2 > $pwm2path &
echo 0 > $pwm1en
echo 0 > $pwm2en


until [ $T0 -lt $Tmaxhyst ]
  do sleep 0.25
  T0=$(cat $temp1)
  echo T0 = $T0
    if [ $T0 -gt $t5 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f5
        done
         }
    elif [ $T0 -gt $t4 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f4
           done
            }
     elif [ $T0 -gt $t3 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f3
           done
            }
    elif [ $T0 -gt $t2 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f2
           done
            }
    elif [ $T0 -gt $t1 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f1
           done
            }
    elif [ $T0 -lt $t1 ]
      then { 
        for z in {0..7}
          do cpufreq-set -c $z -u $f0
           done
            }
        fi 
done
exec $0 #start from the beginning when cool
