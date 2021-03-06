module Imap::Backup
  class Downloader
    attr_reader :folder
    attr_reader :serializer
    attr_reader :block_size

    def initialize(folder, serializer, block_size: 1)
      @folder = folder
      @serializer = serializer
      @block_size = block_size
    end

    def run
      uids = folder.uids - serializer.uids
      count = uids.count
      Imap::Backup::Logger.logger.debug "[#{folder.name}] #{count} new messages"
      uids.each_slice(block_size).with_index do |block, i|
        offset = i * block_size + 1
        uids_and_bodies = folder.fetch_multi(block)
        if uids_and_bodies.nil?
          if block_size > 1
            Imap::Backup::Logger.logger.debug("[#{folder.name}] Multi fetch failed for UIDs #{block.join(", ")}, switching to single fetches")
            @block_size = 1
            redo
          else
            Imap::Backup::Logger.logger.debug("[#{folder.name}] Fetch failed for UID #{block[0]} - skipping")
            next
          end
        end

        uids_and_bodies.each.with_index do |uid_and_body, j|
          uid = uid_and_body[:uid]
          body = uid_and_body[:body]
          Imap::Backup::Logger.logger.debug(
            "[#{folder.name}] uid: #{uid} (#{offset +j}/#{count}) - " \
              "#{body.size} bytes"
          )
          serializer.save(uid, body)
        end
      end
    end
  end
end
