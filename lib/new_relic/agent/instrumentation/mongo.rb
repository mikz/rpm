# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

DependencyDetection.defer do
  named :mongo

  depends_on do
    defined?(::Mongo)
  end

  executes do
    if defined?(::Mongo::Logging)
      NewRelic::Agent.logger.debug 'Installing Mongo instrumentation'
      install_mongo_instrumentation
    else
      NewRelic::Agent.logger.debug 'Mongo instrumentation requires Mongo::Logging'
    end
  end

  def install_mongo_instrumentation
    ::Mongo::Logging.class_eval do
      include NewRelic::Agent::MethodTracer

      def instrument_with_newrelic_trace(name, payload = {}, &block)
        payload = {} if payload.nil?
        collection = payload[:collection]

        if collection == '$cmd'
          f = payload[:selector].first
          name, collection = f if f
        end

        trace_execution_scoped('Database/#{collection}/#{name}') do
          t0 = Time.now
          result = instrument_without_newrelic_trace(name, payload, &block)
          NewRelic::Agent.instance.transaction_sampler.notice_sql(payload.inspect, nil, (Time.now - t0).to_f)
          result
        end
      end

      alias_method :instrument_without_newrelic_trace, :instrument
      alias_method :instrument, :instrument_with_newrelic_trace
    end
  end
end
