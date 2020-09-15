#!/usr/bin/python
#  -*- coding: utf-8 -*-

"""
showLines

    show lines from a file based on a range of times.
    requires that the first field (column) of the file is a time field

See the usage method for more information and examples.

"""
# Imports: native Python
import argparse
import datetime
import gc
import hashlib
import json
import logging
import logging.handlers
import os
import os.path
import random
import socket
import sys
from uuid import uuid1

# 3rd party imports
from confluent_kafka import Producer, Consumer, KafkaError, OFFSET_BEGINNING, OFFSET_END, OFFSET_STORED, OFFSET_INVALID


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

#    data['name'] = os.path.basename(file).encode('ascii', 'xmlcharrefreplace')
#    data['folder'] = os.path.abspath(os.path.dirname(file)).encode('ascii', 'xmlcharrefreplace')

#    data['mount_point'] = os.path.dirname(file)
#    data['mount_source'] = os.path.dirname(file)

#    drive, path = os.path.splitdrive(file)
#    drive, path = os.path.splittext(file)

#    eval "stat_vals=( $(stat --format="['mount_point']='%m' ['time_of_birth']='%w'" "$1") )"
#    local mount_source="$(grep -E '\s'"${stat_vals['mount_point']}"'\s' /etc/fstab | awk '{print $1}')"

    if os.path.islink(file):
        if os.path.exists(file):
            data['symlink_reference'] = os.path.realpath(file)
        else:
            data['symlink_reference'] = None
            data['link_reference'] = os.path.realpath(file)
            return data

    if os.path.isfile(file) and not os.path.islink(file):
        data['sha256'] = hashlib.sha256(open(file, mode='rb').read()).hexdigest()

    stat = os.stat(file)
    data['size'] = stat.st_size
#    data['blocks'] = stat.st_blocks
#    data['block_size'] = stat.blksize

#    data['xfr_size_hint'] = stat.st_size
#    data['device_number'] = stat.st_size
#    data['file_type'] = stat.st_rdev

    data['uid'] = stat.st_uid
#    data['uname'] = stat.st_size
    data['gid'] = stat.st_gid
#    data['gname'] = stat.st_size
    data['access_rights'] = stat.st_mode
#    data['access_rights_time'] = stat.st_size
    data['inode'] = stat.st_ino
    data['hard_links'] = stat.st_nlink
#    data['raw_mode'] = stat.st_size
#    data['device_type'] = stat.st_size
#    data['file_created'] = stat.st_birthtime
#    data['file_created_time'] = zulu_timestamp(stat.birthtime)
    data['last_access'] = int(stat.st_atime)
    data['last_access_time'] = zulu_timestamp(stat.st_atime)
    data['last_modified'] = int(stat.st_mtime)
    data['last_modified_time'] = zulu_timestamp(stat.st_mtime)
    data['last_status_change'] = int(stat.st_ctime)
    data['last_status_change_time'] = zulu_timestamp(stat.st_ctime)
    return data


def uuid1mc_insecure():
    return str(uuid1(random.getrandbits(48) | 0x010000000000))

def zulu_timestamp(tstamp):
    return datetime.datetime.fromtimestamp(tstamp).strftime("%Y-%m-%dT%I:%M:%S.%fZ")


class KafkaProducer(object):
    def __init__(self, server, topic):
        self.topic = topic
        # bootstrap.servers  - A list of host/port pairs to use for establishing the initial connection to the Kafka cluster
        # client.id          - An id string to pass to the server when making requests
        self.kafka = Producer({"bootstrap.servers": server,
                                  "client.id": socket.gethostname()})
        return

    def produce(self, value=None, key=None):
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


class ScanShareFiles:
    """
        CBF VersionUpdater class
    """

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


    def main(self, cmdargs):

        self.logger.debug("Entering main with args: %s" % cmdargs)
        args = GetArgs()
        args.validate_options()
        self.args = args
        self.producer = None
        self.opFile = None

        if args.kafka:
            self.producer = KafkaProducer(args.servers, args.topic)
        else:
            self.opFile = open(args.file, 'w')


        file_count = 0
        dir_count = 0
        prompt=''

        for file in args.dirs:
            for root, dirs, files in os.walk(file):
                dir_count += 1
                '{}.\t[ {}, {} ]\t{} :\t{} files'.format(prompt, dir_count, file_count, root, 10 )
                for name in files:
                    file_count += 1
                    filename = os.path.join(root, name)
                    try:
                        self.saveFileData(filename)
                    except:
                        print ('unable to create JSON for: {}'.format(filename))
                    if (file_count %100) == 0:
                        gc.collect()
                for name in dirs:
                    dir_count += 1



    def saveFileData(self, filename):

        data = fileInfo(filename)
        json_value = json.dumps(data, ensure_ascii=False, indent=None, sort_keys=False)
        del data

        if self.producer:
            self.producer(json_value)

        else:
            f = self.opFile
            f.write(json_value)
            f.flush()
        del json_value




# ### ----- M A I N   D R I V E R   C O D E ----- ### #

if __name__ == "__main__":
    gc.enable()
    out = ScanShareFiles()
    sys.exit(out.main(sys.argv[1:]))
