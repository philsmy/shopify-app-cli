# frozen_string_literal: true
module Rails
  module Commands
    class Create < ShopifyCli::SubCommand
      USER_AGENT_CODE = <<~USERAGENT
        module ShopifyAPI
          class Base < ActiveResource::Base
            self.headers['User-Agent'] << " | ShopifyApp/\#{ShopifyApp::VERSION} | Shopify App CLI"
          end
        end
      USERAGENT

      options do |parser, flags|
        # backwards compatibility allow 'title' for now
        parser.on('--title=TITLE') { |t| flags[:title] = t }
        parser.on('--name=NAME') { |t| flags[:title] = t }
        parser.on('--organization_id=ID') { |url| flags[:organization_id] = url }
        parser.on('--shop_domain=MYSHOPIFYDOMAIN') { |url| flags[:shop_domain] = url }
        parser.on('--type=APPTYPE') { |url| flags[:type] = url }
      end

      def call(args, _name)
        form = Forms::Create.ask(@ctx, args, options.flags)
        return @ctx.puts(self.class.help) if form.nil?

        @ctx.abort(@ctx.message('rails.create.error.invalid_ruby_version')) unless
          Ruby.version(@ctx).satisfies?('~>2.4')

        build(form.name)
        set_custom_ua
        ShopifyCli::Project.write(@ctx, 'rails')

        ShopifyCli::Core::Finalize.request_cd(form.name)

        api_client = ShopifyCli::Tasks::CreateApiClient.call(
          @ctx,
          org_id: form.organization_id,
          title: form.title,
          type: form.type,
          app_url: 'https://shopify.github.io/shopify-app-cli/getting-started',
        )

        ShopifyCli::Resources::EnvFile.new(
          api_key: api_client["apiKey"],
          secret: api_client["apiSecretKeys"].first["secret"],
          shop: form.shop_domain,
          scopes: 'write_products,write_customers,write_draft_orders',
        ).write(@ctx)

        partners_url = "https://partners.shopify.com/#{form.organization_id}/apps/#{api_client['id']}"

        @ctx.puts(@ctx.message('rails.create.info.created', form.title, partners_url))
        @ctx.puts(@ctx.message('rails.create.info.serve', ShopifyCli::TOOL_NAME))
        @ctx.puts(@ctx.message('rails.create.info.install', partners_url, form.title))
      end

      def self.help
        ShopifyCli::Context.message('rails.create.help', ShopifyCli::TOOL_NAME, ShopifyCli::TOOL_NAME)
      end

      private

      def build(name)
        install_gem('rails')
        CLI::UI::Frame.open(@ctx.message('rails.create.installing_bundler')) do
          install_gem('bundler', '~>1.0')
          install_gem('bundler', '~>2.0')
        end

        CLI::UI::Frame.open(@ctx.message('rails.create.generating_app', name)) do
          syscall(%W(rails new --skip-spring #{name}))
        end

        @ctx.root = File.join(@ctx.root, name)

        @ctx.puts(@ctx.message('rails.create.adding_shopify_gem'))
        File.open(File.join(@ctx.root, 'Gemfile'), 'a') do |f|
          f.puts "\ngem 'shopify_app', '>=11.3.0'"
        end
        CLI::UI::Frame.open(@ctx.message('rails.create.running_bundle_install')) do
          syscall(%w(bundle install))
        end

        CLI::UI::Frame.open(@ctx.message('rails.create.running_generator')) do
          begin
            syscall(%w(spring stop))
          rescue
          end
          syscall(%w(rails _5.2.4.2_ generate shopify_app))
        end

        CLI::UI::Frame.open(@ctx.message('rails.create.running_migrations')) do
          syscall(%w(rails db:migrate RAILS_ENV=development))
        end
      end

      def set_custom_ua
        ua_path = File.join('config', 'initializers', 'user_agent.rb')
        @ctx.write(ua_path, USER_AGENT_CODE)
      end

      def syscall(args)
        args[0] = Gem.binary_path_for(@ctx, args[0])
        @ctx.system(*args, chdir: @ctx.root)
      end

      def install_gem(name, version = nil)
        Gem.install(@ctx, name, version)
      end
    end
  end
end

