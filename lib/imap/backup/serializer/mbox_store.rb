require "json"

require "email/mboxrd/message"
require "imap/backup/serializer/mbox_enumerator"

module Imap::Backup
  class Serializer::MboxStore
    CURRENT_VERSION = 2

    attr_reader :folder
    attr_reader :path
    attr_reader :loaded

    def initialize(path, folder)
      @path = path
      @folder = folder
      @loaded = false
      @uids = nil
      @uid_validity = nil
    end

    def exist?
      mbox_exist? && imap_exist?
    end

    def uid_validity
      do_load if !loaded
      @uid_validity
    end

    def uid_validity=(value)
      do_load if !loaded
      @uid_validity = value
      @uids ||= []
      write_imap_file
    end

    def uids
      do_load if !loaded
      @uids || []
    end

    def add(uid, body)
      do_load if !loaded
      raise "Can't add messages without uid_validity" if !uid_validity

      uid = uid.to_i
      if uids.include?(uid)
        Imap::Backup::Logger.logger.debug(
          "[#{folder}] message #{uid} already downloaded - skipping"
        )
        return
      end

      mboxrd_message = Email::Mboxrd::Message.new(body)
      mbox = nil
      begin
        mbox = File.open(mbox_pathname, "ab")
        mbox.write mboxrd_message.to_serialized
        @uids << uid
        write_imap_file
      rescue StandardError => e
        message = <<-ERROR.gsub(/^\s*/m, "")
          [#{folder}] failed to save message #{uid}:
          #{body}. #{e}:
          #{e.backtrace.join("\n")}"
        ERROR
        Imap::Backup::Logger.logger.warn message
      ensure
        mbox&.close
      end
    end

    def load(uid_maybe_string)
      do_load if !loaded
      uid = uid_maybe_string.to_i
      message_index = uids.find_index(uid)
      return nil if message_index.nil?

      load_nth(message_index)
    end

    def each_message(required_uids)
      return enum_for(:each_message, required_uids) if !block_given?

      indexes = required_uids.each.with_object({}) do |uid_maybe_string, acc|
        uid = uid_maybe_string.to_i
        index = uids.find_index(uid)
        acc[index] = uid if index
      end
      enumerator = Serializer::MboxEnumerator.new(mbox_pathname)
      enumerator.each.with_index do |raw, i|
        uid = indexes[i]
        next if !uid

        yield uid, Email::Mboxrd::Message.from_serialized(raw)
      end
    end

    def update_uid(old, new)
      index = uids.find_index(old.to_i)
      return if index.nil?

      uids[index] = new.to_i
      write_imap_file
    end

    def reset
      @uids = nil
      @uid_validity = nil
      @loaded = false
      delete_files
      write_blank_mbox_file
    end

    def rename(new_name)
      new_mbox_pathname = absolute_path("#{new_name}.mbox")
      new_imap_pathname = absolute_path("#{new_name}.imap")
      File.rename(mbox_pathname, new_mbox_pathname)
      File.rename(imap_pathname, new_imap_pathname)
      @folder = new_name
    end

    def mbox_pathname
      absolute_path("#{folder}.mbox")
    end

    def imap_pathname
      absolute_path("#{folder}.imap")
    end

    private

    def do_load
      data = imap_data
      if data
        @uids = data[:uids].map(&:to_i)
        @uid_validity = data[:uid_validity]
        @loaded = true
      else
        reset
      end
    end

    def imap_data
      return nil if !imap_ok?

      imap_data = nil

      begin
        imap_data = JSON.parse(File.read(imap_pathname), symbolize_names: true)
      rescue JSON::ParserError
        return nil
      end

      return nil if !imap_data.key?(:uids)
      return nil if !imap_data[:uids].is_a?(Array)

      imap_data
    end

    def imap_ok?
      return false if !exist?
      return false if !imap_looks_like_json?

      true
    end

    def load_nth(index)
      enumerator = Serializer::MboxEnumerator.new(mbox_pathname)
      enumerator.each.with_index do |raw, i|
        next if i != index

        return Email::Mboxrd::Message.from_serialized(raw)
      end
      nil
    end

    def imap_looks_like_json?
      return false if !imap_exist?

      content = File.read(imap_pathname)
      content.start_with?("{")
    end

    def write_imap_file
      imap_data = {
        version: CURRENT_VERSION,
        uid_validity: @uid_validity,
        uids: @uids
      }
      content = imap_data.to_json
      File.open(imap_pathname, "w") { |f| f.write content }
    end

    def write_blank_mbox_file
      File.open(mbox_pathname, "w") { |f| f.write "" }
    end

    def delete_files
      File.unlink(imap_pathname) if imap_exist?
      File.unlink(mbox_pathname) if mbox_exist?
    end

    def mbox_exist?
      File.exist?(mbox_pathname)
    end

    def imap_exist?
      File.exist?(imap_pathname)
    end

    def absolute_path(relative_path)
      File.join(path, relative_path)
    end
  end
end
