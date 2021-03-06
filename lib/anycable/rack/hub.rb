# frozen_string_literal: true

require "set"

module AnyCable
  module Rack
    # From https://github.com/rails/rails/blob/v5.0.1/actioncable/lib/action_cable/subscription_adapter/subscriber_map.rb
    class Hub
      attr_reader :streams, :sockets

      def initialize
        @streams = Hash.new do |streams, stream_id|
          streams[stream_id] = Hash.new { |channels, channel_id| channels[channel_id] = Set.new }
        end
        @sockets = Hash.new { |h, k| h[k] = Set.new }
        @sync = Mutex.new
      end

      def add_subscriber(stream, socket, channel)
        @sync.synchronize do
          @streams[stream][channel] << socket
          @sockets[socket] << [channel, stream]
        end
      end

      def remove_subscriber(stream, socket, channel)
        @sync.synchronize do
          @streams[stream][channel].delete(socket)
          @sockets[socket].delete([channel, stream])
          cleanup stream, socket, channel
        end
      end

      def remove_channel(socket, channel)
        list = @sync.synchronize do
          return unless @sockets.key?(socket)

          @sockets[socket].dup
        end

        list.each do |(channel_id, stream)|
          remove_subscriber(stream, socket, channel) if channel == channel_id
        end
      end

      def remove_socket(socket)
        list = @sync.synchronize do
          return unless @sockets.key?(socket)

          @sockets[socket].dup
        end

        list.each do |(channel_id, stream)|
          remove_subscriber(stream, socket, channel_id)
        end
      end

      def broadcast(stream, message, coder)
        list = @sync.synchronize do
          return unless @streams.key?(stream)

          @streams[stream].to_a
        end

        list.each do |(channel_id, sockets)|
          decoded = coder.decode(message)
          cmessage = channel_message(channel_id, decoded, coder)
          sockets.each { |socket| socket.transmit(cmessage) }
        end
      end

      def close_all
        hub.sockets.dup.each do |socket|
          hub.remove_socket(socket)
          socket.close
        end
      end

      private

      def cleanup(stream, socket, channel)
        @streams[stream].delete(channel) if @streams[stream][channel].empty?
        @streams.delete(stream) if @streams[stream].empty?
        @sockets.delete(socket) if @sockets[socket].empty?
      end

      def channel_message(channel_id, message, coder)
        coder.encode(identifier: channel_id, message: message)
      end
    end
  end
end
