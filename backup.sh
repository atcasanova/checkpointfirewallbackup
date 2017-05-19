#!/bin/bash
export LANG=en_US.utf8

# CONSTANTES
DIAMES=$(date +%d)
DIR=$(date +%b%y)

# funcao para desenhar mensagens na tela
function drawBox {
	string="$*";
	tamanho=${#string}
	echo -n "+"; for i in $(seq $tamanho); do echo -n "-"; done; echo "+";
	echo -n "|"; echo -n $string; echo "|";
	echo -n "+"; for i in $(seq $tamanho); do echo -n "-"; done; echo "+";
}

pathlocal=/srv/backup/firewall

function bkpcma {
	SRV=$1
	IP=$2
	find $pathlocal/$SRV/ -type f -exec chmod a-w {} +;

	ssh admin@$IP mdsstat >/dev/null && tipo=provider || tipo=gerencia

	# salva STDOUT e STDERR em arquivo log com nome do servidor e data/hora

	exec > /root/scripts/logs/$(date +$SRV-%Y%m%d-%Hh%M).log 2>&1

	# pega versão do firmware
	fwver=$(ssh admin@$IP fw ver | grep -Eo "R[0-9]{2}(\.[0-9]{1,}[A-Z]{1,}){0,}")
	profile=/opt/CPshrd-$fwver/tmp/.CPprofile.sh

	# checa diretório e pega lista de CMAs do servidor
	ssh admin@$IP "[ ! -d /var/log/backups/$SRV ] && mkdir -p /var/log/backups/$SRV || echo Diretorio do provider ja criado"
	[ $tipo == "provider" ] && cmas=$(ssh admin@$IP mdsstat | grep CMA | cut -d"|" -f3)

	# Testa se a variável foi ou não preenchida
	[ ${#cmas} -gt 0 ] && {
		drawBox $cmas encontradas
		# loop em todas as CMAs
		# caso as CMAs existam
		for cma in $cmas
		do
			dataHora=$(date +%d%b%y-%H:%M:%S)
			drawBox "Backup de $cma iniciado ($dataHora)"
			BKPDIR=/var/log/backups/$cma
			BKPFILE=$cma-$(date +%d%b%y).tgz
			caminho=/opt/CPmds-$fwver/customers/$cma/CPsuite-$fwver/fw1
			ssh admin@$IP "[ ! -d $BKPDIR/$DIR ] && mkdir -p $BKPDIR/$DIR || echo Diretorio $BKPDIR/$DIR ja criado"
			ssh admin@$IP "fw logswitch"
			files=$(ssh admin@$IP ls $caminho/log/*201* | grep -v .gz$)
			drawBox gzipando arquivos
			for arq in $files; do ssh admin@$IP "gzip -rcv $arq > $BKPDIR/$DIR/${arq##*/}.gz"; done;
			drawBox eliminando arquivos
			ssh admin@$IP "find $caminho/log/ -name \"*201*\" -print -type f -mtime +3 -exec rm {} +;
							find $caminho/log/ -name \"SPOWVPN*\" -print -type f -mtime +3 -exec rm {} +;" && drawBox "Arquivos eliminados com sucesso" || drawBox "Falha ao deletar arquivos"
			drawBox Logs da CMA $cma compactadas e movidas em $(date +%d%b%y-%H:%M:%S)
			ssh admin@$IP "mdsenv $cma; mcd bin; $caminho/bin/upgrade_tools/migrate export -n $BKPDIR/$DIR/$BKPFILE"
			drawBox Arquivo Gerado: $BKPFILE em $SRV:$BKPDIR/$DIR - $(date +%d%b%y-%H:%M:%S)
			ssh admin@$IP "[ -f $BKPDIR/$DIR/$BKPFILE ] && echo BKP CMA ${cma^^} OK || echo BKP CMA ${cma^^} FALHOU"
			drawBox "Backup de $cma finalizado ($(date +%d%b%y-%H:%M:%S))"
			[ ! -d $pathlocal/$SRV/$cma ] && mkdir -p $pathlocal/$SRV/$cma
			drawBox Copia de $cma iniciada em $(date +%d%b%y-%H:%M:%S)
			scp -rCc arcfour admin@$IP:$BKPDIR/$DIR $pathlocal/$SRV/$cma/ &&
				drawBox Copia finalizada em $(date +%d%b%y-%H:%M:%S) ||
				drawBox Copia de $SRV/$cma falhou - $(date +%d%b%y-%H:%M:%S)
			diff <(ls $pathlocal/$SRV/$cma/$DIR/ | sort) <(ssh admin@$IP "ls $BKPDIR/$DIR/" | sort) || drawBox Diferencas na Copia de $cma
			drawBox Verificando md5sum da copia de $BKPFILE
			md5local=$(md5sum $pathlocal/$SRV/$cma/$DIR/$BKPFILE | cut -f1 -d' ' | sort)
			md5remoto=$(ssh admin@$IP md5sum $BKPDIR/$DIR/$BKPFILE | cut -f1 -d' ' | sort)
			[ "$md5local" == "$md5remoto" ] && drawBox Copia de $BKPFILE finalizada com sucesso || drawBox Copia de $BKPFILE corrompida.
			ssh admin@$IP "find /var/log/backups/ -mtime +10 -type f | xargs  rm -f ;"
		done
	}

	# backup de gerencia
	[ $tipo == "gerencia" ] && {
		BKPDIR=/var/log/backups
		BKPFILE=$SRV-$(date +%Y_%m_%d).tgz
		dataHora=$(date +%d%b%y-%H:%M:%S)
		drawBox Backup da Gerencia $SRV - $dataHora
		ssh admin@$IP "[ ! -d $BKPDIR/$DIR ] && mkdir -p $BKPDIR/$DIR || echo Diretorio $BKPDIR/$DIR ja criado"
		ssh admin@$IP fw logswitch
		drawBox Compactar arquivos de gerencia - $(date +%d%b%y-%H:%M:%S)
 		ssh admin@$IP <<-\SSHEND
						fwver=$(fw ver | grep -Eo "R[0-9]{2}(\.[0-9]{1,}[A-Z]{1,}){0,}")
						BKPDIR=/var/log/backups
						DIR=$(date +%b%y)
						find /opt/CPsuite-$fwver/fw1/log/ -name "*201*" -print0 | while read -d $'\0' fn; do gzip -rcv $fn > $fn.gz; done;
						cp /opt/CPsuite-$fwver/fw1/log/fw.adtlog* $BKPDIR/$DIR;
						mv /opt/CPsuite-$fwver/fw1/log/*201*gz $BKPDIR/$DIR
SSHEND
		dataHora=$(date +%d%b%y-%H:%M:%S)
		drawBox Logs compactadas e movidas - $dataHora
		drawBox Inicio do Export $dataHora
		ssh admin@$IP "cpstop; /opt/CPsuite-$fwver/fw1/bin/upgrade_tools/migrate export -n $BKPDIR/$DIR/export_$BKPFILE ; cpstart &"
		[ ! -d $pathlocal/$SRV/$DIR ] && mkdir -p $pathlocal/$SRV/$DIR
		drawBox Copiando arquivos para $pathlocal/$SRV/$DIR - $(date +%d%b%y-%H:%M:%S)
		echo $BKPDIR/$DIR $pathlocal/$SRV
		scp -rCc arcfour admin@$IP:$BKPDIR/$DIR/ $pathlocal/$SRV/ ||
			drawBox SCP de $SRV Falhou - $(date +%d%b%y-%H:%M:%S)
		md5local=$(md5sum $pathlocal/$SRV/$DIR/export_$BKPFILE | cut -f1 -d' ')
		md5remoto=$(ssh admin@$IP md5sum $BKPDIR/$DIR/export_$BKPFILE | cut -f1 -d' ')
		diff <(ls $pathlocal/$SRV/$DIR/|sort) <(ssh admin@$IP "ls $BKPDIR/$DIR/"|sort) || drawBox Diferencas na Copia de $SRV
		[ "$md5local" == "$md5remoto" ] && drawBox export_$BKPFILE copiado com sucesso || drawBox export_$BKPFILE corrompido.
		dataHora=$(date +%d%b%y-%H:%M:%S)
		drawBox Copia dos arquivos finalizada $pathlocal/$SRV/$DIR - $dataHora
		ssh admin@$IP "find /opt/CPsuite-$fwver/fw1/log/ -name "*201*" -type f -print -mtime +3 -exec rm {} +;"
		ssh admin@$IP "find /var/log/backups/ -type f -name "*201*" -print -mtime +3 | xargs rm -f ;"

	}

	check_mds_logs

	[ $DIAMES -eq 01 ] && {
		BKPDIR=/var/log/backups/
    	[ ! -d $pathlocal/$SRV/$DIR ] && mkdir -p $pathlocal/$SRV/$DIR
		[ $tipo == "provider" ] && {
			# provider
	        drawBox Iniciando Backup do Provider $SRV - $(date +%d%b%y-%H:%M:%S)
	        ssh admin@$IP "[ ! -d $BKPDIR/$SRV/$DIR ] && mkdir -p $BKPDIR/$SRV/$DIR || echo Diretorio $BKPDIR/$SRV/$DIR já criado"
	        ssh admin@$IP "mds_backup -g -L best -b -l -d /var/log/backups/$SRV/$DIR/"
			scp -rC admin@$IP:$BKPDIR/$SRV/$DIR $pathlocal/$SRV/ || drawBox SCP de $SRV/$cma falhou!
			diff <(ls $pathlocal/$SRV/$DIR/|sort) <(ssh admin@$IP "ls $BKPDIR/$DIR/"|sort) || drawBox Diferencas na Copia do provider $SRV
    		md5remoto=$(ssh admin@$IP md5sum /var/log/backups/$SRV/$DIR/*.tar.gz | cut -f1 -d' ')
    		md5local=$(md5sum $pathlocal/$SRV/$DIR/*.tar.gz | cut -f1 -d' ')
    		[ "$md5remoto" == "$md5local" ] && {
    			ssh admin@$IP "rm -f /var/log/backups/$SRV-$DIR.tar.gz"
    			drawBox Backup do provider $SRV finalizado. Arquivo remoto removido
    		} || drawBox Copia de $SRV-$DIR.tar.gz corrompida.
	        drawBox Backup do Provider $SRV Finalizado - $(date +%d%b%y-%H:%M:%S)
	    } || {
			# gerencia
		   [ $tipo == "gerencia" ] && {
	    		drawBox cpbackup_util encontrado
	    		drawBox Iniciando Backup do Manager $SRV - $(date +%d%b%y-%H:%M:%S)
   				BKPDIR=/var/log/backups
				BKPFILE=$SRV-$(date +%Y_%m_%d).tgz
	    		ssh admin@$IP "[ ! -d $BKPDIR/$DIR ] && mkdir -p $BKPDIR/$DIR || echo Diretorio $BKPDIR/$DIR já criado"
	    		ssh admin@$IP "cpstop; cpbackup_util backup --file $BKPDIR/$DIR/backup_$BKPFILE --type all; cpstart &"
	    		scp -C admin@$IP:$BKPDIR/$DIR/backup_$BKPFILE $pathlocal/$SRV/$DIR || drawBox SCP de $SRV falhou!
				diff <(ls $pathlocal/$SRV/$DIR/|sort) <(ssh admin@$IP "ls $BKPDIR/$DIR/"|sort) || drawBox Diferencas na Copia da gerencia $SRV
	    		md5remoto=$(ssh admin@$IP md5sum $BKPDIR/$DIR/backup_$BKPFILE | cut -f1 -d' ')
	    		md5local=$(md5sum $pathlocal/$SRV/$DIR/backup_$BKPFILE | cut -f1 -d' ')
	    		[ "$md5remoto" == "$md5local" ] &&	{
	    			drawBox Backup do SmartCenter $SRV Finalizado - $(date +%d%b%y-%H:%M:%S)
	    			ssh admin@$IP rm -f $BKPDIR/$DIR/backup_$BKPFILE
	    		} || drawBox Copia de backup_$BKPFILE corrompida - $(date +%d%b%y-%H:%M:%S)
	    	}
	    }
	}
	find $pathlocal/$SRV/ -type f -exec chmod a-w +;
	chown ctmagent.ctmagent -R /srv/backup/* 2> /dev/null
}

# example: bkcpcma hostname ip


