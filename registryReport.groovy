import groovy.json.*

import java.awt.AttributeValue
//import java.util.Comparator
import java.util.Map

import org.codehaus.groovy.tools.shell.util.Logger

class RepoEntry {
    String digest
    String createTime
    ArrayList<String> tags = []

    RepoEntry(Object data) {
        digest = data.digest
        createTime = data.createTime
        tags = data.tags
    }
    String toString() {
        String out = '       ' + digest + ', ' + createTime + '\n'
        tags.sort().each { k ->
            out += '          ' + k.toString() + '\n'
        }
        out
    }
    int getNumTags() {
        tags.size()
    }
}

class RepoContents {
    String name
    String id
    ArrayList<RepoEntry> digests = []

    RepoContents(Object data) {
        name = data.repository
        id = data.id
        data.digests.each { x ->
            digests += new RepoEntry(x)
        }
    }

    int getNumTags() {
        int count = 0
        digests.each { it ->
            count += it.numTags
        }
        return count
    }

    int getNumImages() {
        digests.size()
    }

    String toString() {
        String out = id + ', ' + name + ', Images: ' + numImages + ', Tags: ' + numTags + '\n'
        digests.sort().each { k ->
            out += k.toString() + '\n'
        }
        out
    }
}

class RegistryData {
    String base
    def log
    ArrayList<RepoContents> repos = []

    RegistryData() {
        base = System.getenv('BASE') ?: '/home/groovy/scripts'
        log = Logger.create(getClass())
        Map json = readJson(System.getenv('JSON'))
        parser(json)
    }

    //-------------------------------------

    private void dumpHash(Object data, File file) {
        if (data) {
    //        println  "saving ${file.absolutePath}"
            if (file.exists()) file.delete()
            def bldr = new JsonBuilder(data)
            file << bldr.toString()
       }
    }

    //-------------------------------------

    private def cleanup(File dir) {
        try {
            println "Cleaning up ${dir.absolutePath}"
            if (dir.exists()) {
                // delete old files
                dir.eachFileRecurse { file ->
                    if (file.isDirectory()) cleanup(file)
                    if (! file.delete())   println "failed to delete: ${file.absolutePath}"
                }
            }
        }
        catch(Exception e) {
            println e.message
        }
    }
    //-------------------------------------

    private def writeJson(int idx, Map chunk)
    {
        def bldr = new JsonBuilder(chunk)
        String id = String.format('%02d', idx)
        def file = new File(base, "cyclone.chunk.${id}.json")
        file << bldr.toString()
    }
    //-------------------------------------



    def readJson(String filename) {

        filename = filename ?: "${base}/registryReport.json"
        def jsonFileData = new File(filename)

        def slurper = new JsonSlurper()
        slurper.parseText('{"data":'+jsonFileData.text+'}')
    }

    def parser(Map json) {
        json.data.each { k ->
            repos += new RepoContents(k)
        }
    }

    String toString() {
        String out = ''
        repos.each { r ->
             out += r.toString()
        }
        out
    }

    def removeOldFiles() {
        def dir = new File(base)
        dir.eachFileRecurse { file ->
            if (file.name =~ /cyclone\.chunk\..+\.json/){
                if (! file.delete())   println "failed to delete: ${file.absolutePath}"
            }
        }

    }
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//     MAIN
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////

def processor = new RegistryData()
def out = new File('/home/groovy/scripts/registryReport.txt')
if ( out.exists() ) {
    out.delete()
}
out << processor.toString()

println 'done.'

''