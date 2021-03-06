module ActiveRecord
  module AttributeMethods
    module TimeZoneConversion
      class TimeZoneConverter < DelegateClass(Type::Value) # :nodoc:
        include Type::Decorator

        def type_cast_from_database(value)
          convert_time_to_time_zone(super)
        end

        def type_cast_from_user(value)
          if value.is_a?(Array)
            value.map { |v| type_cast_from_user(v) }
          elsif value.respond_to?(:in_time_zone)
            begin
              user_input_in_time_zone(value) || super
            rescue ArgumentError
              nil
            end
          end
        end

        def convert_time_to_time_zone(value)
          if value.is_a?(Array)
            value.map { |v| convert_time_to_time_zone(v) }
          elsif value.acts_like?(:time)
            value.in_time_zone
          else
            value
          end
        end
      end

      extend ActiveSupport::Concern

      included do
        mattr_accessor :time_zone_aware_attributes, instance_writer: false
        self.time_zone_aware_attributes = false

        class_attribute :skip_time_zone_conversion_for_attributes, instance_writer: false
        self.skip_time_zone_conversion_for_attributes = []

        class_attribute :time_zone_aware_types, instance_writer: false
        self.time_zone_aware_types = [:datetime, :not_explicitly_configured]
      end

      module ClassMethods
        private

        def inherited(subclass)
          # We need to apply this decorator here, rather than on module inclusion. The closure
          # created by the matcher would otherwise evaluate for `ActiveRecord::Base`, not the
          # sub class being decorated. As such, changes to `time_zone_aware_attributes`, or
          # `skip_time_zone_conversion_for_attributes` would not be picked up.
          subclass.class_eval do
            matcher = ->(name, type) { create_time_zone_conversion_attribute?(name, type) }
            decorate_matching_attribute_types(matcher, :_time_zone_conversion) do |type|
              TimeZoneConverter.new(type)
            end
          end
          super
        end

        def create_time_zone_conversion_attribute?(name, cast_type)
          enabled_for_column = time_zone_aware_attributes &&
            !self.skip_time_zone_conversion_for_attributes.include?(name.to_sym)
          result = enabled_for_column &&
            time_zone_aware_types.include?(cast_type.type)

          if enabled_for_column &&
            !result &&
            cast_type.type == :time &&
            time_zone_aware_types.include?(:not_explicitly_configured)
            ActiveSupport::Deprecation.warn(<<-MESSAGE)
              Time columns will become time zone aware in Rails 5.1. This
              sill cause `String`s to be parsed as if they were in `Time.zone`,
              and `Time`s to be converted to `Time.zone`.

              To keep the old behavior, you must add the following to your initializer:

                  config.active_record.time_zone_aware_types = [:datetime]

              To silence this deprecation warning, add the following:

                  config.active_record.time_zone_aware_types << :time
            MESSAGE
          end

          result
        end
      end
    end
  end
end
