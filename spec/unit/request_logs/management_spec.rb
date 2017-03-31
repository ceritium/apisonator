require_relative '../../spec_helper'

module ThreeScale
  module Backend
    module RequestLogs
      describe Management do
        let(:storage) { ThreeScale::Backend::Storage.instance }
        let(:service_id) { '7001' }
        let(:lock_key) { described_class.const_get :GLOBAL_LOCK_KEY }
        let(:services_set_key) { described_class.const_get :SERVICES_SET_KEY }

        describe '.enable_service' do
          before do
            described_class.clean_cubert_redis_keys
            described_class.global_enable
            described_class.disable_service service_id
            described_class.enable_service service_id
          end

          it 'enables service' do
            expect(described_class.enabled? service_id).to be_truthy
          end

          it 'adds an entry to the tracking set' do
            expect(storage.sismember(services_set_key,
              described_class.send(:bucket_id_key, service_id))).to be_truthy
          end
        end

        describe '.disable_service' do
          before do
            described_class.clean_cubert_redis_keys
            described_class.global_enable
            described_class.enable_service service_id
            described_class.disable_service service_id
          end

          it 'disables the service' do
            expect(described_class.enabled? service_id).to be_falsey
          end

          it 'does not leak an entry in the tracking set' do
            expect(storage.sismember(services_set_key,
              described_class.send(:bucket_id_key, service_id))).to be_falsey
          end
        end

        describe '.clean_cubert_redis_keys' do
          before do
            described_class.clean_cubert_redis_keys
            described_class.global_enable
            described_class.enable_service service_id
            described_class.clean_cubert_redis_keys
          end

          it 'removes all the keys' do
            expect(storage.exists lock_key).to be_falsey
            expect(storage.exists services_set_key).to be_falsey
          end
        end
      end
    end
  end
end