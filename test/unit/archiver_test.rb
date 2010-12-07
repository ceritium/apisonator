require File.expand_path(File.dirname(__FILE__) + '/../test_helper')

class ArchiverTest < Test::Unit::TestCase
  def setup
    FakeFS.activate!
    FileUtils.rm_rf(configuration.archiver.path)
  end

  def teardown
    FakeFS.deactivate!
  end

  test 'add_all creates partial file if it does not exist' do
    transaction = {:service_id     => '4001',
                   :application_id => '5001',
                   :usage          => {6001 => 1, 6002 => 224},
                   :timestamp      => Time.utc(2010, 4, 12, 21, 44),
                   :client_ip      => '1.2.3.4'}

    Archiver.add_all([transaction])

    filename = "/tmp/3scale_backend/archive/service-4001/20100412.xml.part"
    assert File.exists?(filename), "File should exist, but it doesn't."

    content = File.read(filename)
    content = "<transactions>#{content}</transactions>"

    doc = Nokogiri::XML(content)

    assert_not_nil doc.at('transaction')
      assert_equal '5001', doc.at('transaction application_id').content
      assert_equal '2010-04-12 21:44:00', doc.at('transaction timestamp').content

      assert_not_nil doc.at('transaction values')
        assert_equal '1',   doc.at('transaction values value[metric_id = "6001"]').content
        assert_equal '224', doc.at('transaction values value[metric_id = "6002"]').content

      assert_equal '1.2.3.4', doc.at('transaction ip').content
  end

  test 'add_all appends to existing partial file' do
    filename = "/tmp/3scale_backend/archive/service-4001/20100412.xml.part"

    # Data already existing in the file
    xml = Builder::XmlMarkup.new
    xml.transaction do
      xml.application_id '5001'
      xml.timestamp      '2010-04-12 21:44:00'
      xml.ip             '1.2.3.4'
      xml.values do
        xml.value '1',   :metric_id => '6001'
        xml.value '224', :metric_id => '6002'
      end
    end

    File.open(filename, 'w') { |io| io.write(xml.target!) }

    transaction = {:service_id     => '4001',
                   :application_id => '5002',
                   :usage          => {6001 => 1, 6002 => 835},
                   :timestamp      => Time.utc(2010, 4, 12, 23, 19),
                   :client_ip      => '1.2.3.5'}


    Archiver.add_all([transaction])

    content = File.read(filename)
    content = "<transactions>#{content}</transactions>"

    doc = Nokogiri::XML(content)

    nodes = doc.search('transaction')

    assert_equal 2, nodes.count

    assert_equal '5001', nodes[0].at('application_id').content
    assert_equal '2010-04-12 21:44:00', nodes[0].at('timestamp').content

    assert_equal '1',   nodes[0].at('values value[metric_id = "6001"]').content
    assert_equal '224', nodes[0].at('values value[metric_id = "6002"]').content

    assert_equal '1.2.3.4', nodes[0].at('ip').content


    assert_equal '5002', nodes[1].at('application_id').content
    assert_equal '2010-04-12 23:19:00', nodes[1].at('timestamp').content

    assert_equal '1',   nodes[1].at('values value[metric_id = "6001"]').content
    assert_equal '835', nodes[1].at('values value[metric_id = "6002"]').content

    assert_equal '1.2.3.5', nodes[1].at('ip').content
  end

  test 'store sends complete files to the archive storage' do
    Archiver.add_all([{:service_id     => 4001,
                       :application_id => 5002,
                       :usage          => {6001 => 1},
                       :timestamp      => Time.utc(2010, 4, 12, 23, 19)}])

    Timecop.freeze(2010, 4, 13, 12, 30) do
      name = nil
      content = nil

      storage = stub('storage')
      storage.expects(:store).with('service-4001/20100412/foo.xml.gz', anything)

      Archiver.store(:storage => storage, :tag => 'foo')
    end
  end

  test 'store does not send incomplete files to the archive storage' do
    Archiver.add_all([{:service_id     => 4001,
                       :application_id => 5002,
                       :usage          => {6001 => 1},
                       :timestamp      => Time.utc(2010, 4, 12, 23, 19)}])

    Timecop.freeze(2010, 4, 12, 23, 44) do
      storage = stub('storage')
      storage.expects(:store).with('service-4001/20100412/foo.xml.gz', anything).never

      Archiver.store(:storage => storage, :tag => 'foo')
    end
  end

  test 'store makes the files valid xml and compresses them' do
    Archiver.add_all([{:service_id     => 4001,
                       :application_id => 5002,
                       :usage          => {6001 => 1},
                       :timestamp      => Time.utc(2010, 4, 12, 23, 19)}])

    Timecop.freeze(2010, 4, 13, 12, 30) do
      name = nil
      content = nil

      storage = stub('storage')
      storage.expects(:store).with do |*args|
        name, content = *args
        true
      end

      Archiver.store(:storage => storage, :tag => 'foo')

      begin
        gzip_io = Zlib::GzipReader.new(StringIO.new(content))
        content = gzip_io.read
      ensure
        gzip_io.close rescue nil
      end

      doc = Nokogiri::XML(content)
      node = doc.at('transactions:root[service_id = "4001"] transaction')

      assert_not_nil node
      assert_equal '5002', node.at('application_id').content
      assert_equal '1', node.at('values value[metric_id = "6001"]').content
      assert_equal '2010-04-12 23:19:00', node.at('timestamp').content
    end
  end

  test 'cleanup deletes processed partial files older than two days' do
    Archiver.add_all([{:service_id     => 4001,
                       :application_id => 5002,
                       :usage          => {6001 => 1},
                       :timestamp      => Time.utc(2010, 4, 12, 23, 19)}])

    path = '/tmp/3scale_backend/archive/service-4001/20100412.xml.part'

    Timecop.freeze(2010, 4, 14, 12, 30) do
      assert  File.exist?(path), "File should exist, but it doesn't."
      Archiver.cleanup
      assert !File.exist?(path), "File should not exist, but it does."
    end
  end

  test 'cleanup does not delete processed partial files not older than two days' do
    Archiver.add_all([{:service_id     => 4001,
                       :application_id => 5002,
                       :usage          => {6001 => 1},
                       :timestamp      => Time.utc(2010, 4, 12, 23, 19)}])

    path = '/tmp/3scale_backend/archive/service-4001/20100412.xml.part'

    Timecop.freeze(2010, 4, 13, 12, 30) do
      Archiver.cleanup
      assert File.exist?(path), "File should exist, but it doesn't."
    end
  end

  test 'cleanup deletes empty directories' do
    FileUtils.mkdir_p('/tmp/3scale_backend/archive/service-4001')

    Archiver.cleanup

    assert !File.exist?('/tmp/3scale_backend/archive/service-4001'),
           "Directory should be deleted, but it still exists"
  end

  test 'cleanup does not delete non-empty directories' do
    Archiver.add_all([{:service_id     => 4001,
                       :application_id => 5002,
                       :usage          => {6001 => 1},
                       :timestamp      => Time.utc(2010, 12, 4)}])

    Archiver.add_all([{:service_id     => 4001,
                       :application_id => 5002,
                       :usage          => {6001 => 1},
                       :timestamp      => Time.utc(2010, 12, 7)}])

    Timecop.freeze(2010, 12, 7) do
      Archiver.cleanup
      assert File.exist?('/tmp/3scale_backend/archive/service-4001'),
             "Directory should not have been deleted, but it was"
    end
  end
end
