#!groovy

import java.util.Calendar
import java.util.Date
import java.util.TimeZone
import groovy.xml.MarkupBuilder

def call(json) {

    def builder = new MarkupBuilder()
    builder.html {
        head {
            title 'Pipeline test'
            style (type:"text/css", '''
                  .bigPaddingAndGreen {
                      margin: 30px;
                      padding: 30px;
                      background-color: #00FF00
                  }
            ''')
        }
        body {
            h1 'Pipeline test'
            p 'The following are the uptimes reported by each system.'
            table {
                tr {
                   td 'system'
                   td 'time'
                   td 'uptime'
                   td 'uerCount'
                   td '01min averages'
                   td '05min averages'
                   td '45min averages'

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
    return builder.toString()
}
