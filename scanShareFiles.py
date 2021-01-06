#!/usr/bin/python
#  -*- coding: utf-8 -*-

"""
scanShareFiles

    scan a folder and produce JSON stream of attributes foreach file found

See the usage method for more information and examples.

"""
# Imports: native Python
import argparse
import codecs
import datetime
import gc
import grp
import hashlib
import io
import json
import logging
import logging.handlers
import os
import os.path
import pwd
import random
import re
import socket
#import stat
import sys
import tempfile
import traceback
from stat import *
from encodings.aliases import aliases
#from PyJsonFriendly import JsonFriendly
from uuid import uuid1

# 3rd party imports
#from confluent_kafka import Producer, Consumer, KafkaError, OFFSET_BEGINNING, OFFSET_END, OFFSET_STORED, OFFSET_INVALID


BLKSIZE = 131072


#-----------------------------------------------------------------------------
def usage():
    """
        Description:
    """
    examples = """

Usage:
    $progname <folder> <folder> <folder>

"""
    return examples


#-----------------------------------------------------------------------------
def fileInfo(file, data):

    data['file'] = file

    data['name'] = os.path.basename(file)
    data['folder'] = os.path.dirname(file)
    data['depth'] = file.count('/')


    for key in ['dir_count', 'file_count', 'size']:
        if key in data.keys():
            del data[key]


    try:
        fstat = os.stat(file)
        data['blocks'] = fstat.st_blocks
        data['block_size'] = fstat.st_blksize
        data['device'] = fstat.st_dev
        data['device_type'] = fstat.st_rdev
        data['gid'] = fstat.st_gid
        if groupName(fstat.st_gid):
            data['gname'] = groupName(fstat.st_gid)
        elif 'gname' in data.keys():
            del data['gname']
        data['hard_links'] = fstat.st_nlink
        data['inode'] = fstat.st_ino
        data['last_access'] = int(fstat.st_atime)
        data['last_access_time'] = zulu_timestamp(fstat.st_atime)
        data['last_modified'] = int(fstat.st_mtime)
        data['last_modified_time'] = zulu_timestamp(fstat.st_mtime)
        data['last_status_change'] = int(fstat.st_ctime)
        data['last_status_change_time'] = zulu_timestamp(fstat.st_ctime)
        data['mode_8'] = oct(fstat.st_mode)
#        data['mode_x'] = stat.filemode(fstat.st_mode)
        data['size'] = fstat.st_size
        data['type'] = fileType(fstat.st_mode)
        data['uid'] = fstat.st_uid
        if userName(fstat.st_uid):
            data['uname'] = userName(fstat.st_uid)
        elif 'uname' in data.keys():
            del data['uname']

    except:
        for key in ['blocks', 'block_size', 'device', 'device_type', 'gid', 'gname', 'hard_links', 'inode', 'last_access', 'last_access_time', 'last_modified', 'last_modified_time', 'last_status_change', 'last_status_change_time', 'mode_8', 'mode_x', 'size', 'type', 'uid', 'uname']:
            if key in data.keys():
                del data[key]


    if os.path.islink(file):
        if os.path.exists(file):
            data['reference'] = os.path.realpath(file)
            data['isvalid'] = 'true'
        else:
            data['reference'] = os.path.realpath(file)
            data['isvalid'] = 'false'
        return data


    for key in ['reference', 'isvalid']:
        if key in data.keys():
            del data[key]


    if not os.path.isdir(file):
        data['sha256'] = sha256(file, fstat.st_size)


    return data


#def fileInfo_toadd(name, path, data):
#    data['mount_point'] = path
#    data['mount_source'] = path

#    drive, path = os.path.splitdrive(file)
#    drive, path = os.path.splittext(file)

#    eval "stat_vals=( $(stat --format="['mount_point']='%m' ['time_of_birth']='%w'" "$1") )"
#    local mount_source="$(grep -E '\s'"${stat_vals['mount_point']}"'\s' /etc/fstab | awk '{print $1}')"

#    data['xfr_size_hint'] = fstat.st_size
#    data['device_number'] = fstat.st_size

#    data['access_rights_time'] = fstat.st_size
#    data['raw_mode'] = fstat.st_size
#    data['device_type'] = fstat.st_size

#    data['file_created'] = fstat.st_birthtime
#    data['file_created_time'] = zulu_timestamp(fstat.birthtime)
#    return data


#-----------------------------------------------------------------------------
def groupName(gid):
    try:
        return grp.getgrgid(gid)[0]
    except:
        return None


#-----------------------------------------------------------------------------
def userName(uid):
    try:
        return pwd.getpwuid(uid)[0]
    except:
        return None


#-----------------------------------------------------------------------------
def fileType(mode):
    if S_ISBLK(mode):
        return "block device"
    if S_ISCHR(mode):
        return "character device"
    if S_ISDIR(mode):
        return "directory"
    if S_ISFIFO(mode):
        return "FIFO/pipe"
    if S_ISLNK(mode):
        return "symlink"
    if S_ISREG(mode):
        return "regular file"
    if S_ISSOCK(mode):
        return "socket"
    return "unknown"


#-----------------------------------------------------------------------------
def sha256(file, size):
    if size > 0:
        sha = hashlib.sha256()
        if size > BLKSIZE:
            size = BLKSIZE
        with open(file, mode='rb') as fd:
            bytes = fd.read(size)
            while bytes != "":
                sha.update(bytes)
                bytes = fd.read(size)
        return sha.hexdigest()
    return ''

#-----------------------------------------------------------------------------
def uuid1mc_insecure():
    return str(uuid1(random.getrandbits(48) | 0x010000000000))

#-----------------------------------------------------------------------------
def zulu_timestamp(tstamp):
    return datetime.datetime.fromtimestamp(tstamp).strftime("%Y-%m-%dT%I:%M:%S.%fZ")


#-----------------------------------------------------------------------------
class GetArgs:

    def __init__(self):
        """
        Description:
            Parse the arguments given on command line.

        Returns:
            Namespace containing the arguments to the command. The object holds the argument
            values as attributes, so if the arguments dest is set to "myoption", the value
            is accessible as args.myoption
        """
        # parse any command line arguments
        p = argparse.ArgumentParser(description='scan one or more files or folders and output JSON file data',
                                    epilog=usage(),
                                    formatter_class=argparse.RawDescriptionHelpFormatter)
        p.add_argument('-k', '--kafka', action='store_true', help='send to kafka')
        p.add_argument('-t', '--topic', required=False, default=None, type=str, help='kafka topic to send to')
        p.add_argument('-s', '--servers', required=False, default=None, type=str, help='kafka brokers')
        p.add_argument('-f', '--file', required=False, default='files.json', type=str, help='name of file to save JSON')
        p.add_argument('dirs', nargs=argparse.REMAINDER, help='one or more files or folders')

        args = p.parse_args()
        self.dirs = args.dirs
        self.kafka = args.kafka
        self.topic = args.topic
        self.servers = args.servers
        self.file = args.file


    def validate_options(self):
        """
        Description:
            Validate the correct arguments are provided and that they are the correct type

        Raises:
            ValueError: If request_type or request_status are not one of the acceptable values

        """
        if self.kafka:
            if self.servers is None:
                self.servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS')
            if self.servers is None:
                raise ValueError('No kafka servers defined')
            if self.topic is None:
                raise ValueError('No kafka topic defined')

        if len(self.dirs) == 0:
            raise ValueError('No directories or files defined')

        return


#-----------------------------------------------------------------------------
class FileProducer(object):
    def __init__(self, filename, topic = ''):
        self.filename = filename
        self.opFile = open(filename, 'wt')
        self.topic = topic
        return

    def close(self):
        self.opFile.close()

    def produce(self, value=None, key=None):
        try:
            my_json =  json.dumps(value)
            self.save(my_json)
        except:
            exc_type, exc_value, exc_traceback = sys.exc_info()
            traceback.print_exception(exc_type, exc_value, exc_traceback, limit=2, file=sys.stdout)
            for key in value:
                print "   {}: ".format(key),
        finally:
            return
        

    def save(self, info):
        self.opFile.write(info + "\n")
        self.opFile.flush()



#-----------------------------------------------------------------------------
class KafkaProducer(object):
    def __init__(self, server, topic):
        self.topic = topic
        # bootstrap.servers  - A list of host/port pairs to use for establishing the initial connection to the Kafka cluster
        # client.id          - An id string to pass to the server when making requests
 #       self.kafka = Producer({"bootstrap.servers": server,
 #                                 "client.id": socket.gethostname()})
        return

    def produce(self, value=None, key=None):
#        json_objects = dict()

        # Convert value and key to utf-8 format
        json_objects = json.loads(value)
        json_objects['timestamp'] = zulu_timestamp()
        json_objects['uuid'] = uuid1mc_insecure()

        input_data = dict()
        input_data["topic"] = self.topic

        input_data["value"] = json.dumps(json_objects)
        input_data["key"] = key

        self.logger.debug("Input Data to produce: \n %s" % input_data)
        self.kafka.produce(**input_data)
        # flush() - Wait for all messages in the Producer queue to be delivered
        self.kafka.flush()

    def close(self):
        self.kafka.close()


#-----------------------------------------------------------------------------
class ScanShareFiles:

    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.logger.setLevel(logging.DEBUG)

        # create file handler which logs even debug messages
        fh = logging.FileHandler('version_updater.log')
        fh.setLevel(logging.DEBUG)

        # create console handler with a higher log level
        ch = logging.StreamHandler()
        ch.setLevel(logging.ERROR)

        # create formatter and add it to the handlers
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        fh.setFormatter(formatter)
        ch.setFormatter(formatter)

        # add the handlers to the logger
        self.logger.addHandler(fh)
        self.logger.addHandler(ch)

        self.producer = None
        self.opFile = None
        self.dirs = dict()
        self.changes = 0
        self.file_count = 0
        self.dir_count = 0


    def main(self, cmdargs):
        args = GetArgs()
        args.validate_options()
        self.args = args

        args.validate_options()
        self.args = args
        if args.kafka:
            self.producer = KafkaProducer(args.servers, args.topic)
        else:
            self.producer = FileProducer(args.file, args.topic)

#        args.dirs = ['/mnt/Synology/Guest/All Users/Music.todo/20100822/Music.Partial/Tool']

        self.data = dict()

        for dir in args.dirs:
            print('dirs:  '+dir)
#            self.convert(dir)
            self.produceData(dir)
#            self.fixDirs(dir)
#            self.listDirs(dir)
#            self.listFiles(dir)
#            self.showDirs(dir)
#            self.testNames(dir)
        self.producer.close()


    def produceData(self, basedir):
        file_count = 0
        dir_count = 0
        sha = hashlib.sha256()
        size = 0

        for name in os.listdir(basedir):
            file = os.path.join(basedir, name)

            if os.path.isdir(file):
                dir_count += 1
                self.produceData(file)

            else:
                file_count += 1
                fileInfo(file, self.data)
                self.producer.produce(self.data)

            if 'size' in self.data.keys():
                size += self.data['size']

            if 'sha256' in self.data.keys():
                sha.update(self.data['sha256'])


        fileInfo(basedir, self.data)
        self.data['size'] = size
        self.data['file_count'] = file_count
        self.data['dir_count'] = dir_count
        self.data['sha256'] = sha.hexdigest()
        self.producer.produce(self.data)

        print ('   detected {} dirs and {} files on {}'.format(dir_count, file_count, basedir))


#-----------------------------------------------------------------------------

# ### ----- M A I N   D R I V E R   C O D E ----- ### #

if __name__ == "__main__":
    out = ScanShareFiles()
    sys.exit(out.main(sys.argv[1:]))
