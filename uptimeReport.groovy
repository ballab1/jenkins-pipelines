#!groovy

import java.util.Calendar
import java.util.Date
import java.util.TimeZone
import java.util.Map
import groovy.xml.MarkupBuilder
import groovy.json.*


class JsonData {
    Map json

    //-------------------------------------
    JsonData(String jsonFile) {
        this.json = readJson(jsonFile).data
    }

    //-------------------------------------
    def readJson(String filename) {
        def jsonFileData = new File(filename)

        def slurper = new JsonSlurper()
        slurper.parseText('{"data":'+jsonFileData.text+'}')
    }

    //-------------------------------------
    String report() {
        def writer = new StringWriter()
        def builder = new MarkupBuilder(writer)
        builder.div {
            style (type:"text/css", '''
.bigPaddingAndGreen {
  margin: 30px;
  padding: 30px;
  background-color: #00FF00
}
'''
            )
            div {
                h1 'Pipeline test'
                p 'The following are the uptimes reported by each system.'
                table {
                    tr {
                       td 'system'
                       td 'time'
                       td 'uptime'
                       td 'userCount'
                       td '01 min averages'
                       td '05 min averages'
                       td '45 min averages'
                    }
                    json.each { key1, val1 ->
                        tr {
                            td key1
                            val1.each { key2, val2 ->
                                if (key2 == 'load') {
                                    val2.each { key3, val3 ->
                                        td val3
                                    }
                                }
                                else {
                                    td val2
                                }
                            }
                        }
                    }
                }
                Calendar cal = Calendar.getInstance();
                cal.setTimeZone(TimeZone.getTimeZone("UTC"));
                Date now = cal.getTime();
                p 'Generated at: ' + now
            }
        }
        return writer.toString()
    }
}
//////////////////////////////////////////////////////////////////////////////////////////////////////////
//
//     MAIN
//
//////////////////////////////////////////////////////////////////////////////////////////////////////////

def base = System.getenv('BASE') ?: './'
def jsonFile = System.getenv('JSON') ?: "${base}/uptime.json"
def processor = new JsonData(jsonFile)

def out = new File("${base}/report.html")
if ( out.exists() ) {
    out.delete()
}
out << processor.report()

'SUCCESS'
