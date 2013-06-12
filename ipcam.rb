#!/usr/bin/env ruby

require 'net/http'
require 'securerandom'
require 'sinatra'
require 'thread'
require 'RMagick'

$FRAME_SEP = "--ipcamera"

module CamHax
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
                elsif line.length == 0
                else
                    @buffer = @buffer + line
                end
            end
        end
    end

    class ImageStreamer

        def initialize(cam_url, cam_path, cam_user, cam_pass, num_frames)
            @cam_url  = cam_url
            @cam_path = cam_path
            @cam_user = cam_user
            @cam_pass = cam_pass
            @frame_count = 0
            @frame_ptr = 0
            @frames = Array.new(num_frames)
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
                            save_snap(image) unless image.nil?
                        end
                    end
                end
            end
        end

        def frame_count
            @frame_count
        end

        def save_snap(image)
            # save frames in a circular buffer
            @frame_ptr = (@frame_ptr + 1) % @frames.length
            @frames[@frame_ptr] = image
            @frame_count += 1
        end

        def snap
            @frames[@frame_ptr]
        end

        # return an in-order array of current frames
        def frames
            latest_frames = Array.new(@frames.length)
            ptr = @frame_ptr + 1
            @frames.length.times do |i|
                frame = @frames[ptr % @frames.length]
                latest_frames[i] = frame unless frame.nil?
                ptr += 1
            end
            latest_frames
        end

        def with_image_files(&block)
            result = ""
            f = frames
            filenames = Array.new(f.length)
            begin
                f.length.times do |i|
                    filenames[i] = "/tmp/#{SecureRandom.hex}.jpg"
                    File.open(filenames[i], 'wb') do |fd|
                        fd.write(f[i])
                    end
                end
                result = yield filenames
            rescue
                puts "error writing temp files"
            end
            filenames.each do |fn|
                File.unlink(fn) unless fn.nil?
            end
            result
        end
    end
end

cam_url  = ENV['CAM_URL']
cam_path = ENV['CAM_PATH']
cam_user = ENV['CAM_USER']
cam_pass = ENV['CAM_PASS']
shared_secret = ENV['SHARED_SECRET']

streamer = CamHax::ImageStreamer.new(cam_url, cam_path, cam_user, cam_pass, 10)

set :bind, "0.0.0.0"

before '/*' do
    if !shared_secret.nil?
        halt 401 unless params[:secret].eql?(shared_secret)
    end
end

get '/latest.jpg' do
    content_type 'image/jpg'
    streamer.snap
end

get '/latest.gif' do
    content_type 'image/gif'
    outfile = "/tmp/#{SecureRandom.hex}.gif"
    streamer.with_image_files do |image_files|
        animation = Magick::ImageList.new(*image_files)
        animation.delay = 10
        animation.write(outfile)
    end
    image = File.read(outfile)
    File.unlink(outfile)
    image
end

Thread.abort_on_exception = true
Thread.new do
    streamer.run
end

