#!/usr/bin/env ruby

require 'net/http'
require 'securerandom'
require 'sinatra'
require 'spawnling'

$FRAME_SEP = "--ipcamera"

class ImageBuffer
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

class ImageStreamer
    def initialize(cam_url, cam_path, cam_user, cam_pass)
        @cam_url  = cam_url
        @cam_path = cam_path
        @cam_user = cam_user
        @cam_pass = cam_pass
    end
    def run()
        uri = URI(@cam_url)
        Net::HTTP.start(uri.host, uri.port) do |http|
            size = 0
            request = Net::HTTP::Get.new(@cam_path)
            request.basic_auth @cam_user, @cam_pass
            http.request request do |response|
                image_buf = ImageBuffer.new
                response.read_body do |chunk|
                    image_buf.process_chunk(chunk) do |image|
                        fn = "image-" + SecureRandom.hex + ".jpg"
                        File.open(fn, 'wb') do |f|
                            f.write(image)
                        end
                        @current_image = image
                    end
                end
            end
        end
    end
    def snap
        @current_image
    end
end

cam_url  = ENV['CAM_URL']
cam_path = ENV['CAM_PATH']
cam_user = ENV['CAM_USER']
cam_pass = ENV['CAM_PASS']

streamer = ImageStreamer.new(cam_url, cam_path, cam_user, cam_pass)
get '/' do
    content_type 'image/jpg'
    streamer.snap
end

Spawnling.new(:method => :threading) do
    streamer.run
end

