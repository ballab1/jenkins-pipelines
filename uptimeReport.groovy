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
    String getLineClass(line) {
        return (line % 2) ? 'td a1' : 'td a0'
    }

    //-------------------------------------
    String report() {
        def writer = new StringWriter()
        def builder = new MarkupBuilder(writer)
        int line = 0
        builder.expandEmptyElements = true
        builder.escapeAttributes = false
        builder.div {
            style (type:'text/css', '''
.table {
  display: table;
  margin: 5px;
  padding: 5px;
}
.tr {
  display: table-row;
  width: 100%;
}
.td {
  display: table-cell;
  padding: 10px;
  border: 1px solid black;
  text-align: left;
}
.a0 {
  background-color: #F0F0F0;
}
.a1 {
  background-color: white;
}
.center {
  text-align: center;
}
.header {
  background-color: blue;
  color: white;
}
.info {
  width: 100px;
  height: 30px;
}
.title {
  font-size: 25pt;
  font-weight: bold;
  padding: 10px 10px 10px 10px;
  text-align: center;
}
'''
            )
            div {
                h1 'Pipeline test'
                p 'The following are the uptimes reported by each system.'
                div (class:'table') {
                    div (class:'tr') {
                       div (class:'td header info', 'system')
                       div (class:'td header info', 'time')
                       div (class:'td header info', 'uptime')
                       div (class:'td header') { mkp.yieldUnescaped('user<br>count') }
                       div (class:'td header') { mkp.yieldUnescaped('01 min<br>averages') }
                       div (class:'td header') { mkp.yieldUnescaped('05 min<br>averages') }
                       div (class:'td header') { mkp.yieldUnescaped('45 min<br>averages') }
                    }
                    json.each { key1, val1 ->
                        div (class:'tr') {
                            div (class:'td header', key1)
                            val1.each { key2, val2 ->
                                if (key2 == 'load') {
                                    val2.each { key3, val3 ->
                                        div (class:getLineClass(line), val3)
                                    }
                                }
                                else {
                                    div (class:getLineClass(line), val2)
                                }
                            }
                        }
                        line++
                    }
                }
                Calendar cal = Calendar.getInstance();
                cal.setTimeZone(TimeZone.getTimeZone('UTC'));
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
