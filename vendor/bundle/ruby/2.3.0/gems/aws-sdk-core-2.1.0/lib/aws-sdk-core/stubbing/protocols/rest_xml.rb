module Aws
  module Stubbing
    module Protocols
      class RestXml < Rest

        include Seahorse::Model::Shapes

        def body_for(api, operation, rules, data)
          xml = []
          builder = Aws::Xml::DocBuilder.new(target: xml, indent: '  ')
          rules.location_name = operation.name + 'Result'
          rules['xmlNamespace'] = { 'uri' => api.metadata['xmlNamespace'] }
          Xml::Builder.new(rules, target:xml).to_xml(data)
          xml.join
        end

        def stub_error(error_code)
          http_resp = Seahorse::Client::Http::Response.new
          http_resp.status_code = 400
          http_resp.body = <<-XML.strip
<ErrorResponse>
  <Error>
    <Code>#{error_code}</Code>
    <Message>stubbed-response-error-message</Message>
  </Error>
</ErrorResponse>
          XML
          http_resp
        end

        def xmlns(api)
          api.metadata['xmlNamespace']
        end

      end
    end
  end
end
