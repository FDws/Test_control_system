#!/bin/bash

#check the user's permission
needroot(){
	echo Need root permission!
	exit 1
}
ls /root 1>/dev/null 2>&1 || needroot

#Loading the conf file
if [ ! -f conf/test.conf ] 
then
	echo Do not find the test.conf! 
	exit 1
fi
source conf/test.conf 

#Get the test's time length
alltime=$(($time*60))

#set the pipe's path
noticepipe=/tmp/notice
submitpipe=/tmp/submit

#set the submited student list file
submitstudent=/tmp/submitstudent

#declare the infomation array of all students
declare -A info

#declare the warn array
declare -A warn

#the notice command 
notice(){
	cat $attention | write $1
}
#the submit command
submit(){
	user=$1
	endtest $user
	forceout $user

	echo $user >> /tmp/submitstudent
	echo Submit:$user
}

#forced kill the user
forceout(){
	para=(`who | grep $1`)

	tty=${para[1]}
	if [ ${#para[@]} -ne 0 ]
	then
		pkill -kill -t $tty
	fi
}
#move the exam file to student's main directory
movefile(){
	echo Login :$1
	root=`pwd`

	#delete the exist exam file
	[ -e /home/$1/$1 ] && rm -rf /home/$1/$1

	
	if [ -f $exam ]
	then
		cp $exam /home/$1/$1
		chmod 666 /home/$1/$1
	elif [ -d $exam ]
	then
		mkdir /home/$1/$1

		if [ ! -f $exam/exam.tar ] 
		then
			cd $exam
			tar -cf exam.tar *
			cd $root
		fi

		cd $exam
		cp exam.tar /home/$1/$1
		cd /home/$1/$1
		tar -xf exam.tar 
		chmod 666 *
		rm exam.tar
		cd $root
	else
		echo No such file or directory:$exam
		exit 1
	fi
	
	notice $1
}
#when test finish , move the result to $result directory
endtest(){
	resultdir=$result
	[ -d $resultdir ] || mkdir $resultdir
	[ -e /home/$1/$1 ] && mv /home/$1/$1 $resultdir
}
#inition the warn time array and the information array
init(){
	index=0
	for time in ${warntime[@]}
	do
		#save the second between begin and warn time 
		warn[$index]=$(($alltime-$time*60))
		let index=index+1
	done

	k=`cat conf/studentlist`
	#stu=(ip, used timek warn times)
	stu=(0 0 ${#warn[@]})
	for x in ${k[@]}
	do
		info[$x]=${stu[@]}
	done
}
begin(){
	#the notice process
	{
		while((1))
		do
			student=`cat $noticepipe`
			for stu in ${student[@]}
			do
				[ $stu = "done" ] && break 2
				notice $stu
			done
		done
		rm $noticepipe
	}&
	#the submit process
	{
		while((1))
		do
			student=`cat $submitpipe`
			for stu in ${student[@]}
			do
				[ $stu = "done" ] && break 2 
				submit $stu
			done
		done
		rm $submitpipe
	}&

	#main process
	while((1))
	do
		sleep 1
		current=(`date`)
		currenttime=${current[3]}

		#produce the user list who on line now
		[ -f /tmp/nowlogin ] && rm /tmp/nowlogin
		who | while read line
		do
			name=`echo $line | cut -d' ' -f1`
			ip=`echo $line | cut -d'(' -f2 | cut -d')' -f1`
			echo $name=$ip >> /tmp/nowlogin
		done

		if [ -f /tmp/nowlogin ]
		then
			for line in `cat /tmp/nowlogin`
			do
				name=`echo $line | cut -d'=' -f1`
				ip=`echo $line | cut -d'=' -f2`

				#get one user's infomation
				student=(${info[$name]})
				#if the user are not in student list, continue 
				[ -z ${student[0]} ]  && continue

				#if the user was submited, kill her
				commit=(`cat $submitstudent | grep $name`)
				[ ${#commit[@]} -ne 0 ] && forceout $name && continue

				#if student[1]==0, first time log in, move exam file to user, save the ip
				[ "${student[1]}" = "0" ] && movefile $name && student[0]=$ip

				#if the log in ip is not save as before, log out
				[ "${student[0]}" != "0" ] && [ "${student[0]}" != "$ip" ] && forceout $name

				#time going...
				let student[1]=student[1]+1
				
				#user used all time , forced submit, change the ip to a submit flag 
				if [ ${student[1]} -ge $alltime ] || [ $currenttime = $finishtime ]
				then
				   	student[0]="-1" 
				   	submit $name
				fi

				#when time is warn time, send massage to user
				index=$((${#warn[@]}-${student[2]}))
				if [ $index -lt ${#warn[@]} ]
				then
					if [ ${student[1]} -eq ${warn[$index]} ]
					then
			   			echo "You have only ${warntime[$index]} minutes!" | write $name
						let student[2]=student[2]-1
					fi
				fi

				#update the user's information
				info[$name]=${student[@]}
			done
		fi
		[ $finishtime = $currenttime ] && quit
	done
}
quit(){
	#send flag content, exis the child process
	echo done > $noticepipe
	echo done > $submitpipe

	echo
	date
	echo 'End test!'
	[ -e $submitstudent ] && rm $submitstudent
	[ -e /tmp/nowlogin ] && rm /tmp/nowlogin
	[ -e /bin/notice ] && rm /bin/notice
	[ -e /bin/submit ] && rm /bin/submit
	exit 0
}

#check the pipe
[ -p "$noticepipe" ] || mkfifo $noticepipe 
chmod +662 $noticepipe
[ -p "$submitpipe" ] || mkfifo $submitpipe
chmod +662 $submitpipe

#check the notice and submit command
[ -f /bin/notice ] || cp $notice /bin || echo No such file:$notice
[ -f /bin/submit ] || cp $submit /bin || echo No such file:$submit

#check the submitstudent file
[ -f $submitstudent ] && rm $submitstudent
touch $submitstudent

[ -e $result ] && rm -rf $result

chmod 555 /bin/notice
chmod 555 /bin/submit

#produce the studentlist
[ -f "conf/studentlist" ] || conf/createListFile.sh || exit 1

trap "quit" 2

#wait for begin
echo begintime: $begintime
echo finishtime:$finishtime
while((1))
do
	[ $begintime = "now" ] && break

	now=(`date`)
	[ ${now[3]} = $begintime ] && break 
	sleep 1
done

date
echo Test begin...

init
begin

exit 0
