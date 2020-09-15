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
import stat
import sys
import tempfile
import traceback
from encodings.aliases import aliases
#from PyJsonFriendly import JsonFriendly
from uuid import uuid1

# 3rd party imports
#from confluent_kafka import Producer, Consumer, KafkaError, OFFSET_BEGINNING, OFFSET_END, OFFSET_STORED, OFFSET_INVALID


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

MOUNTS = [ "Guest/All Users.backups_300/Music",
           "Guest/All Users/Music.todo/20100619.Music.org",
           "Guest/All Users/Music.todo/20100702/Music",
           "Guest/All Users/Music.todo/20100702/Music.ToDo",
           "Guest/All Users/Music.todo/20100717/Music.Partial",
           "Guest/All Users/Music.todo/20100717/Music.ToDo",
           "Guest/All Users/Music.todo/20100822/Music",
           "Guest/All Users/Music.todo/20100822/Music.Partial",
           "Guest/All Users/Music.todo/20100822/Music.ToDo",
           "Guest/All Users/Music.todo/Music.300gb-DRIVE",
           "Guest/All Users/Music.todo",
           "Guest/All Users",
           "Public/Shared Music"
         ]


DIRS = [ "Ace Of Base/The Bridge",
         "Bright Eyes/Digital Ash In A Digital Urn",
         "Eagles/The Long Run",
         "Faust/Faust IV",
         "Frank Zappa/Chunga's Revenge",
         "Franz Ferdinand/Franz Ferdinand",
         "JO",
         "Jean-Michel Jarre",
         "Jethro Tull/Living In The Past (disc 1)",
         "Level 42/True Colours",
         "OutKast/Speakerboxxx-The Love Below Disc 2",
         "Sansa/Albums",
         "Santana/Zebop!",
         "Spyro Gyra/Carnaval",
         "Style Council",
         "Vangelis",
         "Wendy Carlos/Switched On Bach II"
        ]


MODES = { stat.S_IFSOCK : 'socket',
          stat.S_IFLNK  : 'symlink',
          stat.S_IFREG  : 'regular file',
          stat.S_IFBLK  : 'block device',
          stat.S_IFDIR  : 'directory',
          stat.S_IFCHR  : 'character device',
          stat.S_IFIFO  : 'FIFO/pipe'
        }

BLKSIZE = 131072

#-----------------------------------------------------------------------------
def fileInfo(name, path, data):
    data['name'] = to_unicode_or_bust(name)
    data['folder'] = to_unicode_or_bust(path)

    file = os.path.join(path, name)

    if os.path.islink(file):
        for key in data.keys():
            if key not in ['name', 'folder']:
                del data[key]

        if os.path.exists(file):
            data['symlink_reference'] = os.path.realpath(file)
        else:
            data['link_reference'] = os.path.realpath(file)
        return data
    else:
        for key in ['symlink_reference', 'link_reference']:
            if key in data.keys():
                del data[key]

    stat = os.stat(file)
    data['size'] = stat.st_size
    data['blocks'] = stat.st_blocks
    data['block_size'] = stat.st_blksize
    data['uid'] = stat.st_uid
    data['uname'] = userName(stat.st_uid)
    data['gid'] = stat.st_gid
    data['gname'] = groupName(stat.st_gid)
    data['access_rights'] = oct(stat.st_mode)
    data['inode'] = stat.st_ino
    data['hard_links'] = stat.st_nlink
    data['st_dev'] = stat.st_rdev
    data['file_type'] = fileType(stat.st_rdev)
    data['last_access'] = int(stat.st_atime)
    data['last_access_time'] = zulu_timestamp(stat.st_atime)
    data['last_modified'] = int(stat.st_mtime)
    data['last_modified_time'] = zulu_timestamp(stat.st_mtime)
    data['last_status_change'] = int(stat.st_ctime)
    data['last_status_change_time'] = zulu_timestamp(stat.st_ctime)

    if os.path.isfile(file) and not os.path.islink(file):
        data['sha256'] = sha256(file, stat.st_size)
    elif 'sha256' in data.keys():
        del data['sha256']
    return data


def fileInfo_toadd(name, path, data):
#    data['mount_point'] = path
#    data['mount_source'] = path

#    drive, path = os.path.splitdrive(file)
#    drive, path = os.path.splittext(file)

#    eval "stat_vals=( $(stat --format="['mount_point']='%m' ['time_of_birth']='%w'" "$1") )"
#    local mount_source="$(grep -E '\s'"${stat_vals['mount_point']}"'\s' /etc/fstab | awk '{print $1}')"

#    data['xfr_size_hint'] = stat.st_size
#    data['device_number'] = stat.st_size

#    data['access_rights_time'] = stat.st_size
#    data['raw_mode'] = stat.st_size
#    data['device_type'] = stat.st_size

#    data['file_created'] = stat.st_birthtime
#    data['file_created_time'] = zulu_timestamp(stat.birthtime)
    return data


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
    mode = stat.S_IFMT(mode)
    if mode in MODES.keys():
        return MODES[mode]
    return 'unknown'


#-----------------------------------------------------------------------------
def sha256(file, size):
    if size > 0:
        if size > BLKSIZE:
            size = BLKSIZE
        with open(file, mode='rb') as fd:
            sha = hashlib.sha256()
            bytes = fd.read(size)
            while bytes != "":
                sha.update(bytes)
                bytes = fd.read(size)
            return sha.hexdigest()
    return ''


#-----------------------------------------------------------------------------
def to_unicode_or_bust(s, extended = False):
    if all(ord(c) < 128 for c in s):
        return s
    if isinstance(s, unicode):
        return s
    try:
        return unicode(s, 'windows_1250')
    except:
       pass

    if extended:
        keys = ['windows_1251', 'windows_1252', 'windows_1253', 'windows_1254', 'windows_1256', 'windows_1257', 'windows_1258', '1250', '1251', '1252', '1253', '1254', '1255', '1256', '1257', '1258', 'iso8859', 'iso8859_1', 'iso_8859_1', 'iso_8859_13', 'iso_8859_15', 'iso_8859_16', 'iso_8859_16_2001', 'iso_8859_1_1987', 'iso_8859_7', 'iso_8859_7_1987', 'iso_8859_8', 'iso_8859_8_1988', 'iso_8859_9', 'iso_8859_9_1989', 'iso_ir_100', 'iso_ir_126', 'iso_ir_138', 'iso_ir_148', 'l1', 'l10', 'l5', 'l5', 'l7', 'l9', 'latin', 'latin1', 'latin1', 'latin10', 'latin5', 'latin7', 'latin9', 'cp154', 'cp819', 'csisolatin1', 'csisolatin5', 'csisolatingreek', 'csisolatinhebrew', 'csptcp154', 'cyrillic_asian', 'ecma_118', 'elot_928', 'greek', 'greek8', 'hebrew', 'ibm819', 'pt154']
        for t in keys:
           try:
               x =  unicode(s, t)
               print'{} '.format(t),
               print x
           except:
               pass
        print ''
        exit()

    return s


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
                print to_unicode_or_bust(value[key], True)
        

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


    def fixDirs(self, basedir):
        for root, dirs, files in os.walk(basedir):
            for name in files:
                if is_not_ascii(name):
                   to_unicode_or_bust(name),
                   print ('   {}:  {} -> '.format(root,name))
                self.file_count += 1
            for name in dirs:
                if is_not_ascii(name):
                   to_unicode_or_bust(name),
                   print ('   {}:  {} -> '.format(root,name))
                self.dir_count += 1


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

        args.validate_options()
        self.args = args
        if args.kafka:
            self.producer = KafkaProducer(args.servers, args.topic)
        else:
            self.producer = FileProducer(args.file, args.topic)

#        args.dirs = ['/mnt/Synology/Guest/All Users/Music.todo/20100702/Music/Wendy Carlos/Switched On Bach II',
#                     '/mnt/Synology/Guest/All Users/Music.todo/20100619.Music.org/Faust/Faust IV']

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
        data = dict()
        for root, dirs, files in os.walk(basedir):
            for name in files:
                self.file_count += 1
                fileInfo(name, root, data)
                self.producer.produce(data)
        print ('   detected {} files on {}'.format(self.file_count, basedir))


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
