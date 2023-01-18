#!/bin/bash
# shellcheck disable=SC2086

if [[ $0 =~ ^.*functions.sh$ ]]; then
  cat <<EOF
Lista funkcji:
  cleanDisk
  makeStdPartition
  makeVolumes
  mountAll
  umountAll
  change_kernelparams
  ssh_config
  override_initrd_scripts
  bocm_top (in initramfs only)
  bocm_bottom (in initramfs only)
EOF
  exit
fi

set -E
function handle_exception() {
    local _lineno="${1:-LINENO}"
    local _bash_lineno="${2:-BASH_LINENO}"
    local _last_code_line="${3}"
    local _last_command="${4}"
    local _code="${5}"

    local -a _output_array=()

    _output_array+=(
        "  "
        "*** Exception ***"
        "  "
        "   Source line: ${_last_code_line}"
        "       Command: ${_last_command}"
        "   Line number: $_lineno"
        "Function_trace: [${FUNCNAME[*]:1}] ${BASH_LINENO[*]::$((${#FUNCNAME[@]}-1))}"

        "     Exit code: ${_code}"
        "  "
        "***************"
    )

    printf '%s\n' "${_output_array[@]}" >&2

    [[ $(type -t panic) == function ]] && panic || exit ${_code}
}

trap 'handle_exception "${LINENO}" "${BASH_LINENO}" "${BASH_COMMAND}" "$(eval echo ${BASH_COMMAND})" "${?}"' ERR


# Load default, then allow override.
HOSTNAME="$(hostname)"

# shellcheck disable=SC1090
source ${BOCMDIR}/default

# Poprawa wbudowywanej automatycznie configuracji lvm.conf
sed -i -e 's/use_lvmetad = 1/use_lvmetad =0/g' /etc/lvm/lvm.conf

_unsetArrays() {
  unset conf_diskdev
  unset partition__number
  unset partition__name
  unset partition__type
  unset partition__fstype
  unset partition__mnt
  unset partition__mntopt
  unset partition__size
  unset volume__part
  unset volume__name
  unset volume__dev
  unset volume__fstype
  unset volume__size
  unset volume__mnt
  unset volume__mntopt
  unset volume__raid
}

# Funkcja zastępuje polecenie by dodac w kazdym wypadku parametr
# --config "global { use_lvmetad = 0 }"
# lvm() {
#   # Jezeli initramfs
#   if [ "x$init" != "x" ]; then
#     sed -i -e 's/use_lvmetad = 1/use_lvmetad =0/g' /etc/lvm/lvm.conf
#     RESULT=$(/sbin/lvm "$@" --config "global { use_lvmetad = 0 }")
#   else
#     RESULT=$(/sbin/lvm "$@")
#   fi
#   echo -e "$RESULT"
# }

# Funkcja zwraca jednoznaczny, niezmienny w czasie identyfikator dysku
# Wejscie:
#   _devDisk - sciezka do dysku np. /dev/sda
# Wyjscie:
#   _diskID - identyfikator dysku poprzedzony znakiem _
_getDiskID() {
  local _devDisk=$1
  local _diskID=""

  #read MINOR MAJOR < <(stat -c '%T %t' ${_devDisk}) 
  #_diskID=${MAJOR}_${MINOR}

  #_diskID=_$(lsblk --nodeps -no serial ${_devDisk}|sed 's/-\| /_/g')
  # Na vSphere czasem nie ma numeru seryjnego dysku
  #if [ -z ${_devDisk} ]; then
  #  _diskDev=_${_diskDev#/dev}_nosn
  #fi

  # Uwaga awk $4 prawidlowe tylko w initramfs, w normalnym shelu awk $9
  # shellcheck disable=SC2010
  _diskID=$(ls -l /dev/disk/by-path|grep ${_devDisk#/dev/}|grep -v part|awk '{print $4}'|sed 's/pci-\|:\|-\|\./_/g'|sed -E 's/(0)+/0/g')
  printf '%s' ${_diskID}
}

# Funkcja zwraca nazwe dysku "/dev/sda" dla podanego w parametrze identyfikatora "/dev/disk/by-path/...."
# Wejscie:
#   _volFile - sciezka do pliku opisu dysku, prartycji, wolumenow. Domyslanie ${VOLUMES_FILE}
# Wyjscie:
#   _diskName - nazwa dysku
# shellcheck disable=SC2120
_getDiskName() {
  local _devID=""
  local _devName=""
  local _volFile=${1:-${VOLUMES_FILE}}

  if [ -f ${_volFile} ]; then
    # shellcheck disable=SC1090
    source ${BOCMDIR}/bash-yaml/script/yaml.sh

    create_variables "${_volFile}"
    # shellcheck disable=SC2154
    _devID=${conf_diskdev}
  else
    printf '%s' "Can't find volumes definition file: ${_volFile}"
    exit 1
  fi

  # Jezeli _devID nie jest krotka nazwa /dev/sdX lub /dev/nvmeXnX
  if ! echo ${_devID}|grep -qE '\/dev\/sd[a-z]|\/dev\/nvme[0-9]n[0-9]'; then
    _devName=/dev/$(udevadm info -q name "${_devID}")
    if ! [ -b ${_devName} ]; then
      panic "Bad boot device ${_devID}"
      exit 1
    fi
  else
    _devName=${_devID}
  fi

  _unsetArrays

  printf '%s' "${_devName}"
}

# Funkcja zwraca wielkosc pamieci RAM w GB (np. 4)
_getMemorySize() {
  local RESULT="0"
  RESULT=$(awk '/MemTotal/{printf("%.2f\n", $2 / 1024)}' </proc/meminfo)
  echo -e "$RESULT"
}

# Funkcja zwraca ilosc dostepnych do zagospodarowania dyskow
# odrzuca urzadzenia srX czyli cdromy
_getDiskCount() {
  local _result="0"

  _result=$(lsblk --nodeps -no name|grep -vc "sr[0-9]")

  printf "%s" "${_result}"
}

# Czyszczenie dysku, wymazuje wszystko bez pytania
# Parametry:
#   _devDisk - sciezka urzadzenia blokowego dysku
# Wynik:
#   numer_bledu - w przypadku wystapienia dowolnego bledu
cleanDisk() {
  local _return=0
  #local _logfile=${LOGFILE:-/dev/null}
  local _logfile=${LOGFILE:-/logfile.log}
  local _devDisk=$1

  local vgs=""
  local pvs=""
  local lvs=""

  printf "%s begin\n" "${FUNCNAME[0]}" >> ${_logfile}

  vgs=$(lvm vgs --noheadings -o vg_name -S pv_name=~"${_devDisk}.*"|awk '{print $1}') 
  for vg in ${vgs}; do
    lvm vgchange -a n ${vg} >> ${_logfile} 2>&1
    lvs=$(lvm lvs --noheadings -o lv_path,devices|grep ${_devDisk}|awk '{print $1}')
    for lv in ${lvs}; do
      lvm lvremove -y -ff ${lv} >> ${_logfile} 2>&1
    done
    # Jezeli to ostatni dysk w vg
    if [ "$(lvm pvs --noheadings -o pv_name -S vg_name=${vg}|wc -l)" = 1 ]; then
      lvm vgremove -y -f ${vg} >> ${_logfile} 2>&1
      continue
    else
      pvs=$(lvm pvs --noheadings -o pv_name -S pv_name=~"${_devDisk}.*"|awk '{print $1}')
      for pv in ${pvs}; do
        lvm vgreduce -y ${vg} ${pv} >> ${_logfile} 2>&1
        lvm pvremove -y -ff ${pv} >> ${_logfile} 2>&1
      done
      #lvm vgreduce --removemissing --force ${vg} >> ${_logfile} 2>&1
      lvm vgchange -a y ${vg} >> ${_logfile} 2>&1
    fi 
  done
  # Czyscimy dysk
  # Czyszczenie sygnatur na wszystkich istniejacych partycjach
  local _PART_SYMBOL=''
  if echo ${_devDisk}|grep -q "nvme"; then _PART_SYMBOL='p'; fi
  local _DISK=''
  _DISK=${_devDisk#/dev/}${_PART_SYMBOL}
  for (( P=1; P<=$(grep -c "${_DISK}[1-9]" /proc/partitions); P++)); do
    wipefs -a -f -q ${_devDisk}${_PART_SYMBOL}${P} >> ${_logfile} 2>&1
  done

  # shellcheck disable=SC2129
  sgdisk -Z ${_devDisk} >> ${_logfile} 2>&1
  /sbin/partprobe ${_devDisk} >> ${_logfile} 2>&1

  printf "%s end\n\n" "${FUNCNAME[0]}" >> ${_logfile}
  return ${_return}
}

# Tworzenie standardowego schematu podzialu dysku na partycje
# Parametry:
#   devDisk - sciezka urzadzenia blokowego dysku
#   partFile - sciezka do pliku z opisem partycji
# Wynieki:
#   numer_bledu - w przypadku wystapienia dowolnego bledu
makeStdPartition() {
  local _return=0
  local _logfile=${LOGFILE:-/logfile.log}
  local _devDisk=$1
  local _partfile=$2

  printf "%s begin\n" "${FUNCNAME[0]}" >> ${_logfile}

  local _SGDISK=/sbin/sgdisk
  local _SEC_SIZE
  _SEC_SIZE=$(lsblk --nodeps -no phy-sec ${_devDisk}|awk '{print $1}' || echo 4096)

  if [ "x${_partfile}" != 'x' ] && [ -f ${_partfile} ]; then
    # shellcheck disable=SC1090
    source ${BOCMDIR}/bash-yaml/script/yaml.sh

    create_variables "${_partfile}"

  # shellcheck disable=2154
  {
    for ((p = 0; p < ${#partition__number[@]}; p++)); do
       # Patch dla dyskow nvme, gdzie numerowanie partycji zaczyna sie litera p
       local part_number=${partition__number[$p]}
       if echo ${_devDisk}|grep -q nvme; then part_number=p${partition__number[$p]}; fi

      ${_SGDISK} -n ${partition__number[$p]}::+${partition__size[$p]} ${_devDisk} -t ${partition__number[$p]}:${partition__type[$p]} -c ${partition__number[$p]}:${partition__name[$p]} >> ${_logfile} 2>&1
      
      case ${partition__fstype[$p]} in
        "vfat") /sbin/mkfs.vfat -F 32 -n ${partition__name[$p]} ${_devDisk}${part_number} >> ${_logfile} 2>&1 ;;
        *) if [ "x${partition__type[$p]}" != 'x8e00' ]; then
            /sbin/mkfs.xfs -s size=${_SEC_SIZE} -f -L ${partition__name[$p]} ${_devDisk}${part_number} >> ${_logfile} 2>&1
          fi
      esac
    done
  }
    /sbin/partprobe ${_devDisk} >> ${_logfile} 2>&1
  fi
  _unsetArrays

  printf "%s end\n\n" "${FUNCNAME[0]}" >> ${_logfile}
  return ${_return}
}

# Tworzenie standardowego schematu podzialu na wolumeny
# Parametry:
#   _devDisk - sciezka urzadzenia blokowego dysku
#   _volFile - sciezka do pliku opisu wolumenow
# Wynieki:
#   return_code = 0 - jesli wszystko przebieglo pomyslnie
#   return_code = 1 - w przypadku wystapienia dowolnego bledu, wyswietlany jest tez komunikat
makeVolumes() {
  local _return=0
  local _logfile=${LOGFILE:-/logfile.log}
  local _devDisk=$1
  local _volFile=$2
  local _vgname=""
  local _lvname=""
  local _makeFS=false

  printf "%s begin\n" "${FUNCNAME[0]}" >> ${_logfile}

  local _SGDISK=${SGDISK:-/sbin/sgdisk}
  #local _SEC_SIZE=$(cat /sys/block/${_devDisk#/dev}/queue/physical_block_size || echo 4096)
  local _SEC_SIZE
  _SEC_SIZE=$(lsblk --nodeps -no phy-sec ${_devDisk}|awk '{print $1}' || echo 4096)

  if [ "x${_volFile}" != 'x' ] && [ -f ${_volFile} ]; then
    # shellcheck disable=SC1090
    source ${BOCMDIR}/bash-yaml/script/yaml.sh

    create_variables "${_volFile}"

  # shellcheck disable=SC2154
  {
    # Tworzenie PV i VG
    for ((v = 0; v < ${#volume__part[@]}; v++)); do
      # Patch dla dyskow nvme, gdzie numerowanie partycji zaczyna sie litera p
       local part_number=${volume__part[$v]} 
       if echo ${_devDisk}|grep -q nvme; then part_number=p${volume__part[$v]}; fi

      # Jezeli nie istnieje PV to utworz
      local npv=""
      npv=$(lvm pvs --noheadings -o pv_name -S pv_name=${_devDisk}${part_number}|awk '{ print $1 }')
      if [ "x$npv" != "x${_devDisk}${part_number}" ]; then
        lvm pvcreate ${_devDisk}${part_number} >> ${_logfile} 2>&1
      fi

      # Parsowanie vgname z nazwy wolumenu zmienna volume_dev np mapper/vgroot-lvroot
      _vgname=${volume__dev[$v]%%-*}
      _vgname=${_vgname##mapper/} 

      # Tworzenie VG
      # Jezeli istnieje VG o podanej nazwie to dodaj PV
      # Jezeli nie istnieje VG o podanej nazwie to utworz i dodaj PV
      local nvg=""
      nvg=$(lvm vgs --noheadings -o vg_name -S vg_name=${_vgname}|awk '{ print $1 }')
      if [[ "x$nvg" == "x${_vgname}" ]]; then
        # Jezeli w VG nie ma PV to dodaj
        local npvinvg=""
        npvinvg=$(lvm vgs --noheadings -o pv_name -S vg_name=${_vgname},pv_name=${_devDisk}${part_number}|awk '{ print $1 }')
        if [[ "x$npvinvg" != "x${_devDisk}${part_number}" ]]; then
          lvm vgextend ${_vgname} ${_devDisk}${part_number} >> ${_logfile} 2>&1
        fi
      else
        lvm vgcreate -y ${_vgname} ${_devDisk}${part_number} >> ${_logfile} 2>&1
      fi
    done

    # Tworzenie LV
    if [ ${_return} == 0 ]; then
      for ((v = 0; v < ${#volume__part[@]}; v++)); do
        _makeFS="false"
        # Parsowanie vgname i lvname z nazwy wolumenu zmienna volume_dev np mapper/vgroot-lvroot
        _lvname=${volume__dev[$v]##*-}
        _vgname=${volume__dev[$v]%%-*}
        _vgname=${_vgname##mapper/}

        if [ "x${volume__fstype[$v]}" == "xswap" ]; then
          if [ ${volume__size[$v]} == "0" ]; then
            volume__size[$v]=$(echo "$(_getMemorySize) $(_getDiskCount)"|awk '{printf("%.2f\n", 2*$1/$2)}')
          fi
          _makeFS="true"
        else
          if [ ${volume__size[$v]} == "0" ]; then
            # Jezeli to ostatni wolumen
            if [ "$v" = "$((${#volume__part[@]}-1))" ]; then
              volume__size[$v]="99%PVS"
              # Doprecyzowanie nazwy ostatniego wolumenu
              _lvname="${_lvname}$(_getDiskID ${_devDisk})"
              volume__dev[$v]="${volume__dev[$v]}$(_getDiskID ${_devDisk})"
            else
              _return=$?
              break
            fi
          fi
        fi

        # Sprawdzenie czy istnieje juz wolumen o podanej nazwie i vg
        local nlv=""
        nlv=$(lvm lvs --noheadings -o lv_name -S vg_name=${_vgname},lv_name=${_lvname}|awk '{ print $1 }')
        if [[ "x$nlv" == "x${_lvname}" ]]; then
          # Jezeli wolument typu SYS skasuj go i utworz na nowo
          if [ "x${volume__type[$v]}" == "xSYS" ]; then
            lvm lvremove -f ${_vgname}/${_lvname} >> ${_logfile} 2>&1
          else
            continue
          fi
        fi

        case "${volume__raid[$v]}" in 
          "raid1")
            # Jezeli istnieje juz LV o podanej nazwie i nie znajduje sie na przetwarzanym PV
            #local nlv=$(lvm lvs --noheadings -o lv_name -S vg_name=${_vgname},lv_name=${_lvname}|awk '{ print $1 }')
            #local devlv=$(lvm lvs --noheadings -o devices -S vg_name=${_vgname},lv_name=${_lvname}|awk '{ print $1 }'|grep ${_devDisk}${part_number})
            #if [[ "x${nlv}" = "x${_lvname}" && "x${devlv}" = "x" ]]; then
            if lvm lvs --noheadings -o lv_name,devices -S vg_name=${_vgname},lv_name=${_lvname}|grep -q ${_devDisk}${part_number}; then
              # Liczba kopii mirror-a
              local stripes
              stripes=$(lvm lvs --noheadings -o stripes -S lv_name=${_lvname}|awk '{ print $1 }')
              printf "Converting logical volume %s to mirror...\n" "${_lvname}"
              #lvm lvconvert -y -m${stripes} --type mirror --mirrorlog core -i 3 /dev/${volume__dev[$v]}
              lvm lvconvert -y -m${stripes} --alloc anywhere /dev/${volume__dev[$v]} >> ${_logfile} 2>&1
              lvm lvchange -ay /dev/${volume__dev[$v]} >> ${_logfile} 2>&1
              local syncP=0
              until [ $syncP = "100" ]; do
                printf "\r"
                syncP=$(lvm lvs --noheadings -o sync_percent -S lv_name=${_lvname}|awk '{ printf "%d\n", $1 }')
                printf " Waitng for ${_lvname} mirror syncing: ${syncP}%%"
                sleep 1
              done
              printf "\ndone\n"
            else
              # Jezeli nie istnieje LV o podanej nazwie
              printf "Creating logical volume %s..." "${_lvname}"
              # Jezeli wielkowsc okreslona procentowo
              # shellcheck disable=SC2046,SC2003
              if [ $(expr index ${volume__size[$v]} %) != "0" ]; then
                lvm lvcreate -y -n ${_lvname} -l ${volume__size[$v]} --wipesignatures y --zero y $_vgname ${_devDisk}${part_number} >> ${_logfile} 2>&1   
              else
                lvm lvcreate -y -n ${_lvname} -L ${volume__size[$v]} --wipesignatures y --zero y $_vgname ${_devDisk}${part_number} >> ${_logfile} 2>&1
              fi
              # shellcheck disable=SC2181
              if [ "$?" != 0 ]; then
                break
              fi
              _makeFS="true"
              printf "done\n"
            fi
          ;;#raid=raid1

          "n")
            # Jezeli wolumen o podanej nazwie juz istnieje, nic nie rob
            local lv
            lv=$(lvm lvs --noheadings -o lv_name -S vg_name=${_vgname},lv_name=${_lvname}|awk '{ print $1 }')
            if [ "x${lv}" == "x${_lvname}" ]; then
              continue
            fi
            printf "Creating logical volume %s..." "${_lvname}"
            # Jezeli wielkowsc okreslona procentowo
            # shellcheck disable=SC2046,SC2003
            if [ $(expr index ${volume__size[$v]} %) != "0" ]; then
              lvm lvcreate -y -n ${_lvname} -l ${volume__size[$v]} --wipesignatures y --zero y $_vgname ${_devDisk}${part_number} >> ${_logfile} 2>&1
            else
              lvm lvcreate -y -n ${_lvname} -L ${volume__size[$v]} --wipesignatures y --zero y $_vgname ${_devDisk}${part_number} >> ${_logfile} 2>&1
            fi
            if [ ${_return} != 0 ]; then
              break
            fi
            _makeFS="true"
            printf "done\n"
          ;; #raid=n
          *)
            printf "Error: Bad value for \"raid\" field for volume %s" "${volume__dev[$v]}"
            if [ ${_return} != 0 ]; then
              break
            fi
          ;;
        esac

        if ${_makeFS}; then
          case ${volume__fstype[$v]} in
            "vfat") /sbin/mkfs.vfat -F 32 /dev/${volume__dev[$v]} >> ${_logfile} 2>&1 ;;
            "xfs") 
              /sbin/mkfs.xfs -s size=${_SEC_SIZE} -f -L ${volume__name[$v]} /dev/mapper/${_vgname}-${_lvname} >> ${_logfile} 2>&1
              ;;
            "swap")
              /sbin/mkswap -L ${_lvname} /dev/${volume__dev[$v]} >> ${_logfile} 2>&1
              ;;
          esac
        fi
      done
    fi # Tworzenie LV
  }
  else
    printf "Error: Volumes file not exist! - %s" "${_volFile}"
  fi
  
  _unsetArrays

  printf "%s end\n\n" "${FUNCNAME[0]}" >> ${_logfile}
  return ${_return=}
}

# Montowanie wszystki systemow plikow do partycji root
# Paramtry:
#   _devDisk - sciezka do dysku np. /dev/sda
#   _rootmnt - sciezka montowania rootfs np. /rootmnt
#   _volFile - sciezka do pliku z opisem wolumenow
# Wyniki:
#   numer_bledu - w przypadku niepowodzenia, ret code = 0
mountAll() {
  local _return=0
  local _logfile=${LOGFILE:-/logfile.log}
  local _devDisk=$1
  local _rootmnt=$2
  local _volFile=$3

  printf "%s begin\n" "${FUNCNAME[0]}" >> ${_logfile}

  if [ "x${_volFile}" != 'x' ] && [ -f ${_volFile} ]; then
    # shellcheck disable=1090
    source ${BOCMDIR}/bash-yaml/script/yaml.sh

    create_variables "${_volFile}"

    # shellcheck disable=2154
    {
    # Montowanie partycji
    log_begin_msg "Mounting all partitions ${_devDisk}"
    for ((p = 0; p < ${#partition__number[@]}; p++)); do
      # Patch dla dyskow nvme, gdzie numerowanie partycji zaczyna sie litera p
       local part_number=${partition__number[$p]}
       if echo ${_devDisk}|grep -q nvme; then part_number=p${partition__number[$p]}; fi

      if [[ "x${partition__mnt[$p]}" != "x" && "x${partition__mnt[$p]}" != "x/" && "x${partition__mnt[$p]}" != "x\"\"" ]]; then
        mkdir -p ${_rootmnt}${partition__mnt[$p]} >> ${_logfile} 2>&1
        
        #if [ -n ${partition__mntopt[$p]} ]; then
        #  partition__mntopt[$p]="-o ${partition__mntopt[$p]}"
        #fi 
        # Nie dzialaja opcje dla part EFI w skrypcie, ale z reki dzialaja. Do wyjasnienia
        partition__mntopt[$p]=""
        mount ${partition__mntopt[$p]} ${_devDisk}${part_number} ${_rootmnt}${partition__mnt[$p]}
      fi
    done
    log_end_msg
    # Montowanie wolumenow LVM
    log_begin_msg "Mounting all volumes"
    for ((v = 0; v < ${#volume__part[@]}; v++)); do
      if [[ "x${volume__mnt[$v]}" != "x" && "x${volume__mnt[$v]}" != "x/" && "x${volume__mnt[$v]}" != "x\"\"" ]]; then
        mkdir -p ${_rootmnt}${volume__mnt[$v]} >> ${_logfile} 2>&1
        if [[ "x${volume__mntopt[$v]}" != "x" && "x${volume__mntopt[$v]}" != "x\"\"" ]]; then
          mount -o ${volume__mntopt[$v]} /dev/${volume__dev[$v]} ${_rootmnt}${volume__mnt[$v]} >> ${_logfile} 2>&1
        else
          mount /dev/${volume__dev[$v]} ${_rootmnt}${volume__mnt[$v]} >> ${_logfile} 2>&1
        fi
        if [ ${_return} != 0 ]; then
          printf "Error mounting volume dev/%s! %s" "${volume__dev[$v]}" "${_return}"
        fi
      fi
    done
    log_end_msg
    }
  else
    _result="Error: Volumes file not exist! - ${_volFile}\n"
  fi

  _unsetArrays

  printf "%s end\n\n" "${FUNCNAME[0]}" >> ${_logfile}
  return ${_return}
}

# Odmontowanie wszystki systemow plikow do partycji root
# Paramtry:
#   rootmnt - sciezka montowania rootfs np. /rootmnt
#   volFile - sciezka do pliku z opisem wolumenow
# Wyniki:
#   numer_bledu - w przypadku niepowodzenia, ret code = 0
umountAll() {
  local _return=0
  local _logfile=${LOGFILE:-/logfile.log}
  local _rootmnt=$1
  local _volFile=$2

  printf "%s begin\n" "${FUNCNAME[0]}" >> ${_logfile}

  if [ "x${_volFile}" != 'x' ] && [ -f ${_volFile} ]; then
    # shellcheck disable=SC1090
    source ${BOCMDIR}/bash-yaml/script/yaml.sh

    create_variables "${_volFile}"

    # Odmontowanie wolumenow LVM
    log_begin_msg "Mounting all volumes"
    for ((v = $((${#volume__part[@]}-1)); v >= 0; v--)); do
      if [[ "x${volume__mnt[$v]}" != "x" && "x${volume__mnt[$v]}" != "x/" && "x${volume__mnt[$v]}" != "x\"\"" ]]; then
        mount | grep -q ${volume__mnt[$v]} >> ${_logfile} 2>&1
        if [ ${_return} = 0 ]; then
          umount ${_rootmnt}${volume__mnt[$v]} >> ${_logfile} 2>&1
        fi
        if [ ${_return} != 0 ]; then
          printf "Error unmounting %s! %s" "${_rootmnt}${volume__mnt[$v]}" "${_return}"
        fi
      fi
    done
    log_end_msg

    # Odmontowanie partycji
    log_begin_msg "Unmounting all partitions"
    for ((p = $((${#partition__number[@]}-1)); p >= 0; p--)); do
      if [[ "x${partition__mnt[$p]}" != "x" && "x${partition__mnt[$p]}" != "x/" && "x${partition__mnt[$p]}" != "x\"\"" ]]; then
        mount | grep -q ${partition__mnt[$p]} >> ${_logfile} 2>&1
        if [ ${_return} = 0 ]; then
          umount ${_rootmnt}${partition__mnt[$p]} >> ${_logfile} 2>&1
        fi
        if [ ${_return} != 0 ]; then
          printf "Error unmounting %s! %s" "${_rootmnt}${partition__mnt[$p]}" "${_return}"
        fi
      fi
    done
    log_end_msg
  else
    _result="Error: Volumes file not exist! - ${_volFile}\n"
  fi

  _unsetArrays

  printf "%s end\n\n" "${FUNCNAME[0]}" >> ${_logfile}
  return ${_return}
}

change_kernelparams() {
  local FILE=$1
  local PARAMS=""

  # shellcheck disable=SC2013
  for P in $(cat /proc/cmdline); do
    if [[ ${P} != BOOT_IMAGE* && ${P} != vmlinuz && ${P} != root=* ]]; then
      if [[ ${P} = '--' ]]; then break; fi
      PARAMS=${PARAMS}' '${P}
    fi
  done
  # FIXIT: Specyficzne dla ubuntu do poprawy
  sed -i -e "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"${PARAMS}\"/g" ${FILE}
}

ssh_config() {
  # Konfiguracja ssh
  mkdir -p /etc/ssh
  echo "StrictHostKeyChecking=no" >>/etc/ssh/ssh_config
}

# Funkcja dostosowuje konfiguracje rclone
# _server - adres serwera
_config_rclone() {
  local _img_server=$1
  local _cfg_server=$2
  sed -ie "s/\${img_server}/${_img_server}/g" ${BOCMDIR}/rclone.conf
  sed -ie "s/\${cfg_server}/${_cfg_server}/g" ${BOCMDIR}/rclone.conf
}

override_initrd_scripts() {
  log_warning_msg "Correcting server address in rclone.conf"
  
  _config_rclone ${IMG_SERVER} ${CFG_SERVER}

  # Jezeli zmienna zdefiniowana
  if [[ "x${IMG_URI}" != 'x' ]]; then
    # Czy konfiguracja istnieje 
    log_begin_msg "Download configuration initrd from CFG:${CFG_PATH}/${INITRD_CONF_PATH}"
      if /bin/rclone --config ${BOCMDIR}/rclone.conf --no-check-certificate ls CFG:${CFG_PATH}/${INITRD_CONF_PATH}/ > /dev/null; then
        echo -ne "\n"
        /bin/rclone --config ${BOCMDIR}/rclone.conf --no-check-certificate copy --no-check-dest -L CFG:${CFG_PATH}/${INITRD_CONF_PATH}/ / || panic "Configuration ${CFG_PATH} download error!"
      else
        log_warning_msg "Download configuration error!"
      fi
    log_end_msg
  fi
}

bocm_top() {
  local _logfile=${LOGFILE:-/logfile.log}

  # shellcheck disable=SC2154
  [ "x$init" = "x" ] && (
    echo "Not initramfs!"
    return 1
  )

  printf "\n************************************\n"
  printf " BOCM vesrion %s\n" "$(cat /etc/bocm/VERSION)"
  printf "**************************************\n\n"

  # Jezeli nie ma synchronizacji nic nie rob
  if [ "x${IMG_URI}" = 'x' ]; then
    return 1 
  fi
  udevadm trigger
  log_warning_msg "Waiting for UDEV 3[sek]..."
  sleep 3

  # Ustawiona zmienna DISK_INFO, przydatny przy pierwszym starcie gdy nie znamy dysku do bootowania
  if [ "x${DISK_INFO}" = 'xy' ]; then
    disk_info
    printf "\n%s" "You can reboot system."
    /bin/sh -i
    exit
  fi

  DISKDEV=$(_getDiskName)
  log_warning_msg "Boot device ${DISKDEV}"
  

  # Zabezpieczenie na wypadek opoznionego pojawienia sie dysku w systemie, wystepuje czesto na rzeczywistym sprzecie
  while [ "x$(ls ${DISKDEV} 2>/dev/null)" != "x${DISKDEV}" ]; do
    printf "No %s disk, waiting...\n" "${DISKDEV}"
    sleep 1
  done

  # Jezeli nie jest zdefiniowane lub ma jedna z wartosci
  if [[ "x${MANUAL_DISK_MANAGE}" =~ ^(x|xn|xno|xfasle|x0)$ ]]; then

    # Jezeli ma jedna z wartosci to Force reinitialization?
    if [[ "x${MAKE_VOLUMES}" =~ ^(xy|xY|xyes|xtrue|x1)$ ]]; then
      log_warning_msg "Node reinitialization requested"

      log_begin_msg "Erasing root disk ${DISKDEV}"
      cleanDisk ${DISKDEV}
      log_end_msg

      log_begin_msg "Make partitions"
      printf "\n"
      makeStdPartition ${DISKDEV} ${VOLUMES_FILE}
      log_end_msg
    fi
    log_begin_msg "Make volumes"
    makeVolumes ${DISKDEV} ${VOLUMES_FILE}
    log_end_msg

    log_begin_msg "Activating volumegroups"
    lvm vgchange -ay >> ${_logfile} 2>&1
    log_end_msg
  else
    panic "Manual disk manage."
  fi
}

bocm_bottom() {
  local _logfile=${LOGFILE:-/logfile.log}
  local rootmnt=${rootmnt}

  [ "x$init" = "x" ] && (
    echo "Not initramfs!"
    return
  )

  if [ "x${IMG_URI}" = 'x' ]; then
    exit
  fi

  # Ustawiona zmienna DISK_INFO, przydatny przy pierwszym starcie gdy nie znamy dysku do bootowania
  if [ "x${DISK_INFO}" = 'xy' ]; then
    exit
  fi

  DISKDEV=$(_getDiskName)

  printf "\n"
  mount -o remount,rw ${rootmnt} || panic "could not remount rw ${rootmnt}"
  mountAll ${DISKDEV} ${rootmnt} ${VOLUMES_FILE}

  log_begin_msg "Downloading system image from IMG:${IMG_PATH}"
    printf "\n"
    local _originalsize=""
    _originalsize=$(/bin/rclone --config ${BOCMDIR}/rclone.conf --no-check-certificate size IMG:${IMG_PATH} --json|sed -E 's/\{"([a-z]+)":([0-9]+)\,"([a-z]+)":([0-9]+)\}/\4/g')
    cd ${rootmnt} || panic "Error! I can't change directory to ${rootmnt}"
    /bin/rclone --config ${BOCMDIR}/rclone.conf --no-check-certificate cat IMG:${IMG_PATH} | pv -s ${_originalsize} | tar -xzf -
    # Skasowanie pozostałości środowiska przygotowania szablinu docker
    if [ -f .dockerenv ]; then
      rm -rf .dockerenv
    fi
    cd /
  log_end_msg

  log_begin_msg "Download configuration from CFG:${CFG_PATH}/"
    printf "\n"
    /bin/rclone --config ${BOCMDIR}/rclone.conf --no-check-certificate copy --create-empty-src-dirs --no-check-dest -L --exclude=boot.ipxe --exclude=.git/** --exclude=initrd.conf/** CFG:${CFG_PATH}/ ${rootmnt}/
  log_end_msg

  log_begin_msg "Installing bootloader, rebuild initramfs"
    # Zabezpieczenie istniejącego fstab przed nadpisaniem
    if [ -f ${rootmnt}/etc/fstab ]; then
      mv ${rootmnt}/etc/fstab ${rootmnt}/etc/fstab.org
    fi
    cp ${BOCMDIR}/fstab ${rootmnt}/etc/fstab

    DIRS="dev proc sys"
    for D in ${DIRS}; do
      if ! [ -d ${D} ]; then mkdir ${D}; fi
      mount -o bind /${D} ${rootmnt}/${D}
    done

    change_kernelparams ${rootmnt}/etc/default/grub
    # chroot ${rootmnt} /bin/bash -c " \
    #     sed -i -e 's/use_lvmetad = 1/use_lvmetad = 0/g' /etc/lvm/lvm.conf \
    #     && update-grub &> /dev/null \
    #     && grub-install --efi-directory=/boot/efi &> /dev/null \
    #     && update-initramfs -c -k all &> /dev/null &> /dev/null \
    #     && sed -i -e 's/use_lvmetad = 0/use_lvmetad = 1/g' /etc/lvm/lvm.conf \
    #     && exit"

    if [ -z ${PRE_BOOT_FILE} ]; then export PRE_BOOT_FILE=/etc/pre_boot; fi

    if [ -f ${rootmnt}${PRE_BOOT_FILE} ]; then
      chmod +x ${rootmnt}${PRE_BOOT_FILE}
      chroot ${rootmnt} /bin/bash -c ${PRE_BOOT_FILE}
    else
      chroot ${rootmnt} /bin/bash -c "\
      update-grub &> /dev/null \
      && mount -t efivarfs none /sys/firmware/efi/efivars \
      && grub-install --efi-directory=/boot/efi &> /dev/null \
      && umount /sys/firmware/efi/efivars \
      && update-initramfs -c -k all &> /dev/null &> /dev/null \
      && exit"
    fi

    if [ -f ${rootmnt}/etc/fstab.org ]; then
      mv ${rootmnt}/etc/fstab.org ${rootmnt}/etc/fstab
    fi

    for D in ${DIRS}; do
      umount ${rootmnt}/${D}
    done

    cd /
log_end_msg

  

# Umieszczenie pliku resolv.conf
  log_begin_msg "Put file resolv.conf"
  ln -sf /run/systemd/resolve/stub-resolv.conf ${rootmnt}/etc/resolv.conf
  log_end_msg

  umountAll ${rootmnt} ${VOLUMES_FILE}
  mount -o remount,ro ${rootmnt} || panic "could not remount ro ${rootmnt}"
}
