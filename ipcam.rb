#!/usr/bin/env ruby

require 'net/http'
require 'securerandom'

$FRAME_SEP = "--ipcamera"

class ImageStreamer
    def initialize
        @buffer = ""
    end
    def process_chunk(chunk, &block)
        chunk.each_line do |line|
            if line.strip.eql?($FRAME_SEP)
                # strip length header before yielding buffer
                yield @buffer[2,@buffer.length-1]
                @buffer = ""
            elsif line.start_with?("Content")
                puts line
            elsif line.length == 0
            else
                @buffer = @buffer + line
            end
        end
    end
end

def main(url, cam_path, user, pass)
    istreamer = ImageStreamer.new
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port) do |http|
        size = 0
        request = Net::HTTP::Get.new(cam_path)
        request.basic_auth user, pass
        http.request request do |response|
            started = false
            current_image = ""
            response.read_body do |chunk|
                istreamer.process_chunk(chunk) do |image|
                    File.open("image-" + SecureRandom.hex + ".jpg", 'wb') do |f|
                        f.write(image)
                    end
                end
            end
        end
    end
end


cam_url  = ENV['CAMURL']
cam_path = ENV['CAMPATH']
cam_user = ENV['CAMUSER']
cam_pass = ENV['CAMPASS']

main(cam_url, cam_path, cam_user, cam_pass)
