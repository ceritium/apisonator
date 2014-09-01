module ThreeScale
  module Backend
    class Application < Core::Application
      module Sets
        include ThreeScale::Backend::HasSet
        has_set :referrer_filters
        has_set :keys
      end

      include Sets
      include Memoizer::Decorator

      def self.load!(service_id, app_id)
        load(service_id, app_id) or raise ApplicationNotFound, app_id
      end
      memoize :load!

      def self.load(service_id, app_id)
        super(service_id, app_id)
      end
      memoize :load

      def self.load_id_by_key(service_id, user_key)
        super(service_id, user_key)
      end
      memoize :load_id_by_key

      def self.exists?(service_id, app_id)
        super(service_id, app_id)
      end
      memoize :exists?

      def self.load_by_id_or_user_key!(service_id, app_id, user_key)

        case

        when app_id && user_key
          raise AuthenticationError
        when app_id
          load!(service_id, app_id)
        when user_key
          app_id = load_id_by_key(service_id, user_key) or raise UserKeyInvalid, user_key
          load(service_id, app_id) or raise UserKeyInvalid, user_key
        else
          raise ApplicationNotFound
        end
      end

      def self.extract_id!(service_id, app_id, user_key, access_token)
        case
        when app_id && user_key
          raise AuthenticationError
        when app_id
          exists?(service_id, app_id) and app_id or raise ApplicationNotFound, app_id
        when user_key
          app_id = load_id_by_key(service_id, user_key) or raise UserKeyInvalid, user_key
          exists?(service_id, app_id) and app_id or raise UserKeyInvalid, user_key
        when access_token
          ## let's not memoize the oauthaccesstoken since this is supposed to change often
          app_id = OAuthAccessTokenStorage.get_app_id(service_id, access_token) or raise AccessTokenInvalid, access_token
          exists?(service_id, app_id) and app_id or raise ApplicationNotFound, app_id
        else
          raise ApplicationNotFound
        end
      end

      def metric_names
        @metric_names ||= {}
      end

      def metric_names=(hash)
        @metric_names = hash
      end

      def metric_name(metric_id)
        metric_names[metric_id] ||= Metric.load_name(service_id, metric_id)
      end

      def usage_limits
        @usage_limits ||= UsageLimit.load_all(service_id, plan_id)
      end

      # Creates new application key and adds it to the list of keys of this application.
      # If +value+ is nil, generates new random key, otherwise uses the given value as
      # the new key.
      def create_key(value = nil)
        Application.incr_version(service_id,id)
        super(value || SecureRandom.hex(16))
      end

      def delete_key(value)
        Application.incr_version(service_id,id)
        super(value)
      end

      def create_referrer_filter(value)
        raise ReferrerFilterInvalid, "referrer filter can't be blank" if value.blank?
        Application.incr_version(service_id,id)
        super(value)
      end

      def delete_referrer_filter(value)
        Application.incr_version(service_id,id)
        super(value)
      end


      def active?
        state == :active
      end
    end
  end
end
