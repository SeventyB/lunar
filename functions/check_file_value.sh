#!/bin/sh

# shellcheck disable=SC2034
# shellcheck disable=SC1090
# shellcheck disable=SC2154

# check_file_value
#
# Audit file values
#
# This routine takes the following values
#
# check_file      = The name of the file to check
# parameter_name  = The parameter to be checked
# seperator       = Character used to seperate parameter name from it's value (eg =)
# correct_value   = The value we expect to be returned
# comment_value   = Character used as a comment (can be #, *, etc)
#                   Needs to be passed as word, e.g. hash, star, bang, semicolon, eq, space, colon
# position        = E.g. after
# search_value    = Additional search term to help locate parameter / value
#
# If the current_value is not the correct_value then it is fixed if run in lockdown mode
# A copy of the value is stored in a log file, which can be restored
#.

check_file_value_with_position () {
  operator="$1"
  check_file="$2"
  parameter_name="$3"
  separator="$4"
  correct_value="$5"
  comment_value="$6"
  position="$7"
  search_value="$8"
  dir_name=$( dirname "$check_file" )
  sshd_test=$( echo "$check_file" | grep "sshd_config" |wc -l)
  if [ ! -f "$check_file" ]; then
    verbose_message "File \"$check_file\" does not exist" "warn"
  fi
  if [ ! -d "$dir_name" ]; then
    verbose_message "Directory \"$dir_name\" does not exist" "warn"
  else
    if [ "$operator" = "set" ]; then
      correct_value="[A-Z,a-z,0-9]"
      operator="is"
    fi
    if [ "$comment_value" = "star" ]; then
      comment_value="*"
    else
      if [ "$comment_value" = "bang" ]; then
        comment_value="!"
      else
        if [ "$comment_value" = "semicolon" ]; then
          comment_value=";"
        else
          comment_value="#"
        fi
      fi
    fi
    if [ $( expr "$separator" : "eq" ) = 2 ]; then
      separator="="
      spacer="\="
    else
      if [ $( expr "$separator" : "space" ) = 5 ]; then
        separator=" "
        spacer=" "
      else
        if [ $( expr "$separator" : "colon" ) = 5 ]; then
          separator=":"
          space=":"
        fi
      fi
    fi
    if [ "$operator" = "is" ] || [ "$operator" = "in" ]; then
      negative="not"
    else
      negative="is"
    fi
    if [ "$id_check" = "0" ] || [ "$os_name" = "VMkernel" ]; then
      cat_command="cat"
      sed_command="sed"
      echo_command="echo"
    else
      cat_command="sudo cat"
      sed_command="sudo sed"
      echo_command="sudo echo"
    fi
    if [ "$check_file" = "/etc/audit/auditd.conf" ]; then
      spacer=" $spacer "
    fi
    if [ "$audit_mode" = 2 ]; then
      restore_file "$check_file" "$restore_dir"
    else
      string="Value of \"$parameter_name\" $operator set to \"$correct_value\" in \"$check_file\""
      verbose_message "$string" "check"
      if [ ! -f "$check_file" ]; then
        if [ "$audit_mode" = 1 ]; then
          increment_insecure "Parameter \"$parameter_name\" $negative set to \"$correct_value\" in \"$check_file\""
          if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ]; then
            line="$parameter_name$separator\"$correct_value\""
            verbose_message "echo \"$parameter_name$separator\"$correct_value\" >> $check_file" "fix"
          else
            line="$parameter_name$separator$correct_value"
            verbose_message "echo \"$parameter_name$separator$correct_value\" >> $check_file" "fix"
          fi
        else
          if [ "$audit_mode" = 0 ]; then
            string="Parameter $parameter_name to $correct_value in $check_file"
            verbose_message "\"$string\"" "set"
            if [ "$check_file" = "/etc/system" ]; then
              reboot=1
              verbose_message "Reboot required" "notice"
            fi
            if [ "$sshd_test" =  "1" ]; then
              verbose_message "Service restart required for SSH" "notice"
            fi
            backup_file $check_file
            if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ] || [ "$check_file" = "/etc/rc.conf" ] || [ "$check_file" = "/boot/loader.conf" ] || [ "$check_file" = "/etc/sysconfig/boot" ]; then
              echo "$parameter_name$separator\"$correct_value\"" >> "$check_file"
            else
              echo "$parameter_name$separator$correct_value" >> "$check_file"
            fi
          fi
          if [ "$ansible" = 1 ]; then
            echo ""
            echo "- name: Checking $string"
            echo "  lineinfile:"
            echo "    path: $check_file"
            echo "    line: '$line'"
            echo "    create: yes"
            echo ""
          fi
        fi
      else
        correct_hyphen=$( echo "$correct_value" |grep "^[\-]" |wc -l )
        if [ "$correct_hyphen" = "1" ]; then
          correct_value="\\$correct_value"
        fi
        param_hyphen=$( echo "$parameter_name" |grep "^[\-]" |wc -l )
        if [ "$param_hyphen" = "1" ]; then
          parameter_name="\\$parameter_name"
        fi
        if [ "$separator" = "tab" ]; then
          check_value=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |awk '{print $2}' |sed 's/"//g' |uniq |egrep "$correct_value" |wc -l )
        else
          if [ "$sshd_test" = "1" ]; then
            check_value=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |cut -f2 -d"$separator" |sed 's/"//g' |sed 's/ //g' |uniq |egrep "$correct_value" |wc -l )
            if [ ! "$check_value" ]; then
              check_value=$( $cat_command $check_file |grep "$parameter_name" |cut -f2 -d"$separator" |sed 's/"//g' |sed 's/ //g' |uniq |egrep "$correct_value" |wc -l )
            fi
          else
            if [ "$search_value" ]; then
              if [ "$operator" = "is" ]; then
                check_value=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |cut -f2 -d"$separator" |sed 's/"//g' |sed 's/ //g' |uniq |egrep "$search_value" |wc -l )
              else
                check_value=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |grep "$separator" |uniq |egrep "$search_value" |wc -l )
              fi
            else
              if [ "$operator" = "is" ]; then
                check_value=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |cut -f2 -d"$separator" |sed 's/"//g' |sed 's/ //g' |uniq |egrep "$correct_value" |wc -l )
              else
                check_value=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |grep "$separator" |uniq |egrep "$correct_value" |wc -l )
              fi
            fi
          fi
        fi
        if [ "$operator" = "is" ] || [ "$operator" = "in" ]; then
          if [ "$check_value"  = "1" ]; then
            test_value=1
          else
            test_value=0
          fi
        else
          if [ "$check_value" = "" ]; then
            test_value=0
          else
            test_value=1
          fi
        fi
        if [ "$ansible" = 1 ]; then
          if [ "$negative" = "not" ]; then
            line="$parameter_name$separator$correct_value"
          else
            line="$comment_value$parameter_name$separator$correct_value"
          fi
          echo ""
          echo "- name: $string"
          echo "  lineinfile:"
          echo "    path: $check_file"
          echo " .  regex: '^$parameter_name'"
          echo "    line: '$line'"
          echo ""
        fi
        if [ "$separator" = "tab" ]; then
          check_parameter=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |awk '{print $1}' )
        else
          check_parameter=$( $cat_command $check_file |grep -v "^$comment_value" |grep "$parameter_name" |cut -f1 -d"$separator" |sed 's/ //g' |uniq )
        fi
        if [ "$test_value" = 0 ]; then
          correct_hyphen=$( echo "$correct_value" |grep "^[\\]" | wc -l)
          if [ "$correct_hyphen" = "1" ]; then
            correct_value=$( echo "$correct_value" |sed "s/^[\\]//g" )
          fi
          param_hyphen=$( echo "$parameter_name" |grep "^[\\]" | wc -l)
          if [ "$param_hyphen" = "1" ]; then
            parameter_name=$( echo "$parameter_name" |sed "s/^[\\]//g" )
          fi
          if [ "$audit_mode" = 1 ]; then
            increment_insecure "Parameter \"$parameter_name\" $negative set to \"$correct_value\" in \"$check_file\""
            if [ "$check_parameter" != "$parameter_name" ]; then
              if [ "$separator" = "tab" ]; then
                verbose_message "echo -e \"$parameter_name\t$correct_value\" >> $check_file" "fix"
              else
                if [ "$position" = "after" ]; then
                  verbose_message "$cat_command $check_file |sed \"s,$search_value,&\n$parameter_name$separator$correct_value,\" > $temp_file" "fix"
                  verbose_message "$cat_command $temp_file > $check_file" "fix"
                else
                  verbose_message "echo \"$parameter_name$separator$correct_value\" >> $check_file" "fix"
                fi
              fi
            else
              if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ] || [ "$check_file" = "/etc/rc.conf" ] || [ "$check_file" = "/boot/loader.conf" ] || [ "$check_file" = "/etc/sysconfig/boot" ]; then
                verbose_message "$sed_command \"s/^$parameter_name.*/$parameter_name$spacer\"$correct_value\"/\" $check_file > $temp_file" "fix"
              else
                verbose_message "$sed_command \"s/^$parameter_name.*/$parameter_name$spacer$correct_value/\" $check_file > $temp_file" "fix"
              fi
              verbose_message "$cat_command $temp_file > $check_file" "fix"
            fi
          else
            if [ "$audit_mode" = 0 ]; then
              verbose_message "Parameter \"$parameter_name\" to \"$correct_value\" in \"$check_file\"" "set"
              if [ "$check_file" = "/etc/system" ]; then
                reboot=1
                verbose_message "Reboot required" "notice"
              fi
              if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file" = "/etc/sshd_config" ]; then
                verbose_message "Service restart required for SSH" "notice"
              fi
              backup_file "$check_file"
              if [ "$check_parameter" != "$parameter_name" ]; then
                if [ "$separator_value" = "tab" ]; then
                  eval "$echo_command -e \"$parameter_name\t$correct_value\" >> $check_file"
                else
                  if [ "$position" = "after" ]; then
                    eval "$cat_command $check_file |sed \"s,$search_value,&\n$parameter_name$separator$correct_value,\" > $temp_file"
                    eval "$cat_command $temp_file > $check_file"
                  else
                    $echo_command "$parameter_name$separator$correct_value" >> "$check_file"
                  fi
                fi
              else
                if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ] || [ "$check_file" = "/etc/rc.conf" ] || [ "$check_file" = "/boot/loader.conf" ] || [ "$check_file" = "/etc/sysconfig/boot" ]; then
                  eval "$sed_command \"s/^$parameter_name.*/$parameter_name$spacer\\"$correct_value\\"/\" $check_file > $temp_file"
                else
                  eval "$sed_command \"s/^$parameter_name.*/$parameter_name$spacer$correct_value/\" $check_file > $temp_file"
                fi
                cat $temp_file > $check_file
                if [ "$os_name" = "SunOS" ]; then
                  if [ "$os_version" != "11" ]; then
                    pkgchk -f -n -p $check_file 2> /dev/null
                  else
                    pkg fix $( pkg search $check_file |grep pkg |awk '{print $4}' )
                  fi
                fi
                rm "$temp_file"
              fi
            fi
          fi
        else
          increment_secure "Parameter \"$parameter_name\" $operator set to \"$correct_value\" in \"$check_file\""
        fi
      fi
    fi
  fi
}

check_file_value () {
  check_file_value_with_position  "$1" "$2" "$3" "$4" "$5" "$6" "" ""
}
