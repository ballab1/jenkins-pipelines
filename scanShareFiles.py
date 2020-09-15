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
import hashlib
import io
import json
import logging
import logging.handlers
import os
import os.path
import random
import re
import socket
import sys
import tempfile
from uuid import uuid1

# 3rd party imports
#from confluent_kafka import Producer, Consumer, KafkaError, OFFSET_BEGINNING, OFFSET_END, OFFSET_STORED, OFFSET_INVALID


def usage():
    """
        Description:
    """
    examples = """

Usage:
    $progname <folder> <folder> <folder>

"""
    return examples


def fileInfo(file):
    data = dict()
    data['name'] = os.path.basename(file)
    data['folder'] = os.path.abspath(os.path.dirname(file))

##    data['name'] = os.path.basename(file).encode('ascii', 'xmlcharrefreplace')
##    data['folder'] = os.path.abspath(os.path.dirname(file)).encode('ascii', 'xmlcharrefreplace')
#
##    data['mount_point'] = os.path.dirname(file)
##    data['mount_source'] = os.path.dirname(file)
#
##    drive, path = os.path.splitdrive(file)
##    drive, path = os.path.splittext(file)
#
##    eval "stat_vals=( $(stat --format="['mount_point']='%m' ['time_of_birth']='%w'" "$1") )"
##    local mount_source="$(grep -E '\s'"${stat_vals['mount_point']}"'\s' /etc/fstab | awk '{print $1}')"
#
#    if os.path.islink(file):
#        if os.path.exists(file):
#            data['symlink_reference'] = os.path.realpath(file)
#        else:
#            data['symlink_reference'] = None
#            data['link_reference'] = os.path.realpath(file)
#            return data
#
#    if os.path.isfile(file) and not os.path.islink(file):
#        data['sha256'] = hashlib.sha256(open(file, mode='rb').read()).hexdigest()
#
#    stat = os.stat(file)
#    data['size'] = stat.st_size
##    data['blocks'] = stat.st_blocks
##    data['block_size'] = stat.blksize
#
##    data['xfr_size_hint'] = stat.st_size
##    data['device_number'] = stat.st_size
##    data['file_type'] = stat.st_rdev
#
#    data['uid'] = stat.st_uid
##    data['uname'] = stat.st_size
#    data['gid'] = stat.st_gid
##    data['gname'] = stat.st_size
#    data['access_rights'] = stat.st_mode
##    data['access_rights_time'] = stat.st_size
#    data['inode'] = stat.st_ino
#    data['hard_links'] = stat.st_nlink
##    data['raw_mode'] = stat.st_size
##    data['device_type'] = stat.st_size
##    data['file_created'] = stat.st_birthtime
##    data['file_created_time'] = zulu_timestamp(stat.birthtime)
#    data['last_access'] = int(stat.st_atime)
#    data['last_access_time'] = zulu_timestamp(stat.st_atime)
#    data['last_modified'] = int(stat.st_mtime)
#    data['last_modified_time'] = zulu_timestamp(stat.st_mtime)
#    data['last_status_change'] = int(stat.st_ctime)
#    data['last_status_change_time'] = zulu_timestamp(stat.st_ctime)
    return data

# codecs.open(filename, mode[, encoding[, errors[, buffering]]])¶
def to_unicode_or_bust(obj, encoding='utf-8'):
    if isinstance(obj, basestring):
        if not isinstance(obj, unicode):
            obj = unicode(obj, encoding)
    return obj

def uuid1mc_insecure():
    return str(uuid1(random.getrandbits(48) | 0x010000000000))

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
        # Convert value to utf-8 format
        f = self.opFile
        f.write(json.dumps(value) + "\n")
        f.flush()

    def save(self, info):
        self.opFile.write(info + "\n")



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


    def change(self, root, file):
        file2 = file
        try:
            file2 = file.decode('cp1252').encode('utf8', 'xmlcharrefreplace')
        finally:
            if file2 != file:
                print ('rename: {} | {}, {}'.format(root,file,file2))
                file = os.path.join(root, file)
                file2 = os.path.join(root, file2)
#                os.renames(file, file2)


    def convert(self, basedir):
        for root, dirs, files in os.walk(basedir):
           for name in files:
               self.change(root, name)
               self.file_count += 1
           for name in dirs:
               self.dir_count += 1
               self.change(root, name)
        print ('   detected {} files on {}'.format(self.file_count, basedir))


    def getDirType(self, dir, files):
        if len(files)>0:
            with tempfile.NamedTemporaryFile(mode='w+t',delete=False) as fh:
                for line in files:
                    fh.write(line)
                fh.close()
                stream = os.popen('file '+fh.name)
                info = stream.read()
                stream.close()
                os.unlink(fh.name)
                return info
        return None


    def listDirs(self, basedir):
        self.producer = FileProducer('utf8.files')
        filelist = []
        lastroot = None   
        for root, dirs, files in os.walk(basedir):
            for name in files:
                if lastroot != root:
                    self.saveDirType(lastroot, filelist)
                    filelist = []
                    lastroot = root
                self.file_count += 1
                filelist.append(name + "\n")
            for name in dirs:
                self.dir_count += 1
        self.saveDirType(lastroot, filelist)
        self.producer.close()
        print ('   detected {} files on {}'.format(self.file_count, basedir))


    def listFiles(self, basedir):
        fh = tempfile.NamedTemporaryFile(mode='w+t', delete=False)
        for root, dirs, files in os.walk(basedir):
            for name in files:
                self.file_count += 1
                file = os.path.join(root, name).decode('cp1252')
                fh.write(file.encode('utf8', 'xmlcharrefreplace') + "\n")
            for name in dirs:
                self.dir_count += 1
        fh.flush()
        fh.close()
        print ('   detected {} files on {}'.format(self.file_count, basedir))
        return fh.name


    def main(self, cmdargs):
        args = GetArgs()
        args.validate_options()
        self.args = args
#        args.dirs = ['/mnt/Synology/Guest/All Users/Music.todo/20100702/Music/Wendy Carlos/Switched On Bach II',
#                     '/mnt/Synology/Guest/All Users/Music.todo/20100619.Music.org/Faust/Faust IV']
        for dir in args.dirs:
            print('dirs:  '+dir)
#            self.convert(dir)
            self.listDirs(dir)
#            self.listFiles(dir)
#            self.showDirs(dir)
#            self.testNames(dir)


    def produceData(self, args, fileList):
        if args.kafka:
            self.producer = KafkaProducer(args.servers, args.topic)
        else:
            self.producer = FileProducer(args.file, args.topic)

        with open(fileList, 'rt') as fd:
           for file in fd:
               file = file.strip()
               data = fileInfo(file)
               self.producer.produce(data)
               del data

        self.producer.close()
        os.unlink(fileList)


    def saveDirType(self, dir, files):
        info = self.getDirType(dir, files)
        if info:
            matches = re.match(r'^.+:\s+(ISO-8859 text).*$', info, re.M)
            if matches:
                self.producer.save(dir)
            


    def showDirs(self, basedir):
        filelist = []
        lastroot = None
        for root, dirs, files in os.walk(basedir):
            for name in files:
                if lastroot != root:
                    self.getDirType(lastroot, filelist)
                    filelist = []
                    lastroot = root
                self.file_count += 1
                filelist.append(name + "\n")
            for name in dirs:
                self.dir_count += 1
        self.getDirType(lastroot, filelist)
        print ('   detected {} files on {}'.format(self.file_count, basedir))


    def testNames(self, basedir):
        fh = open('filenames_utf.txt', mode='w+t')
        for root, dirs, files in os.walk(basedir):
            for name in files:
                self.file_count += 1
#                if not isinstance(name, unicode):
#                    fh.write(root + '/' + name + "\n")
            for name in dirs:
                self.dir_count += 1
                if not isinstance(name, unicode):
                    fh.write(root + '/' + name + "\n")
        fh.flush()
        fh.close()
        print ('   detected {} files on {}'.format(self.file_count, basedir))


#-----------------------------------------------------------------------------

# ### ----- M A I N   D R I V E R   C O D E ----- ### #

if __name__ == "__main__":
    out = ScanShareFiles()
    sys.exit(out.main(sys.argv[1:]))
