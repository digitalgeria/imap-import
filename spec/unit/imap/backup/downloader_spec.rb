describe Imap::Backup::Downloader do
  describe "#run" do
    subject { described_class.new(folder, serializer) }

    let(:body) { "blah" }
    let(:folder) do
      instance_double(
        Imap::Backup::Account::Folder,
        fetch_multi: [{uid: "111", body: body}],
        name: "folder",
        uids: folder_uids
      )
    end
    let(:folder_uids) { %w(111 222 333) }
    let(:serializer) do
      instance_double(Imap::Backup::Serializer::Mbox, save: nil, uids: ["222"])
    end

    context "with fetched messages" do
      specify "are saved" do
        expect(serializer).to receive(:save).with("111", body)

        subject.run
      end
    end

    context "with messages which are already present" do
      specify "are skipped" do
        expect(serializer).to_not receive(:save).with("222", anything)

        subject.run
      end
    end

    context "with failed fetches" do
      specify "are skipped" do
        allow(folder).to receive(:fetch).with("333") { nil }
        expect(serializer).to_not receive(:save).with("333", anything)

        subject.run
      end
    end
  end
end
