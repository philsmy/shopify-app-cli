# frozen_string_literal: true
require 'test_helper'

module Rails
  module Forms
    class CreateTest < MiniTest::Test
      include TestHelpers::Partners

      def setup
        super
        ShopifyCli::ProjectType.load_type(:rails)
      end

      def test_returns_all_defined_attributes_if_valid
        form = ask
        assert_equal(form.name, 'test_app')
        assert_equal(form.title, 'Test App')
        assert_equal(form.organization_id, 42)
        assert_equal(form.shop_domain, 'shop.myshopify.com')
      end

      def test_title_can_be_provided_by_flag
        form = ask(title: 'My New App')
        assert_equal(form.name, 'my_new_app')
        assert_equal(form.title, 'My New App')
      end

      def test_type_can_be_provided_by_flag
        form = ask(type: 'public')
        assert_equal(form.type, 'public')
      end

      def test_type_is_validated
        io = capture_io do
          form = ask(type: "not_a_type")
          assert_nil(form)
        end
        assert_match('Invalid App Type not_a_type', io.join)
      end

      def test_type_is_prompted
        CLI::UI::Prompt.expects(:ask).with('What type of app are you building?').returns('public')
        ask(type: nil)
      end

      def test_user_will_be_prompted_if_more_than_one_organization
        stub_partner_req(
          'all_organizations',
          resp: {
            data: {
              organizations: {
                nodes: [
                  {
                    'id': 421,
                    'businessName': "one",
                    'stores': { 'nodes': [{ 'shopDomain': 'store.myshopify.com' }] },
                  },
                  {
                    'id': 431,
                    'businessName': "two",
                    'stores': {
                      'nodes': [
                        { 'shopDomain': 'other.myshopify.com', 'transferDisabled': true },
                        { 'shopDomain': 'yet-another.myshopify.com' },
                      ],
                    },
                  },
                ],
              },
            },
          },
        )
        CLI::UI::Prompt.expects(:ask).returns(431)
        form = ask(org_id: nil, shop: nil)
        assert_equal(form.organization_id, 431)
        assert_equal(form.shop_domain, 'other.myshopify.com')
      end

      def test_will_auto_pick_with_only_one_org
        stub_partner_req(
          'all_organizations',
          resp: {
            data: {
              organizations: {
                nodes: [{
                  'id': 421,
                  'businessName': "hoopy froods",
                  'stores': { 'nodes': [{ 'shopDomain': 'next.myshopify.com', 'transferDisabled': true }] },
                }],
              },
            },
          },
        )
        io = capture_io do
          form = ask(org_id: nil, shop: nil)
          assert_equal(form.organization_id, 421)
          assert_equal(form.shop_domain, 'next.myshopify.com')
        end
        assert_match(CLI::UI.fmt('Organization {{green:hoopy froods}}'), io.join)
      end

      def test_organization_will_be_fetched_if_id_is_provided_but_not_shop
        stub_partner_req(
          'find_organization',
          variables: { id: 123 },
          resp: {
            data: {
              organizations: {
                nodes: [
                  {
                    id: 123,
                    stores: { nodes: [{ shopDomain: 'shopdomain.myshopify.com', 'transferDisabled': true }] },
                  },
                ],
              },
            },
          }
        )
        form = ask(org_id: 123, shop: nil)
        assert_equal(form.organization_id, 123)
        assert_equal(form.shop_domain, 'shopdomain.myshopify.com')
      end

      def test_it_will_fail_if_no_orgs_are_available
        stub_partner_req(
          'all_organizations',
          resp: { data: { organizations: { nodes: [] } } },
        )

        io = capture_io do
          form = ask(org_id: nil, shop: nil)
          assert_nil(form)
        end
        assert_match('Please visit https://partners.shopify.com/ to create a partners account', io.join)
        assert_match('No organizations available.', io.join)
      end

      def test_returns_no_shop_if_none_are_available
        stub_partner_req(
          'find_organization',
          variables: { id: 123 },
          resp: {
            data: {
              organizations: {
                nodes: [{ id: 123, stores: { nodes: [] } }],
              },
            },
          }
        )

        io = capture_io do
          form = ask(org_id: 123, shop: nil)
          assert_nil form.shop_domain
        end
        log = io.join
        assert_match('No Development Stores available.', log)
        assert_match(CLI::UI.fmt("Visit {{underline:https://partners.shopify.com/123/stores}} to create one"), log)
      end

      def test_autopicks_only_shop
        stub_partner_req(
          'find_organization',
          variables: { id: 123 },
          resp: {
            data: {
              organizations: {
                nodes: [
                  {
                    id: 123,
                    stores: { nodes: [{ shopDomain: 'shopdomain.myshopify.com', 'transferDisabled': true }] },
                  },
                ],
              },
            },
          }
        )
        io = capture_io do
          form = ask(org_id: 123, shop: nil)
          assert_equal(form.shop_domain, 'shopdomain.myshopify.com')
        end
        assert_match(CLI::UI.fmt("Using Development Store {{green:shopdomain.myshopify.com}}"), io.join)
      end

      def test_prompts_user_to_pick_from_shops
        stub_partner_req(
          'find_organization',
          variables: { id: 123 },
          resp: {
            data: {
              organizations: {
                nodes: [
                  {
                    id: 123,
                    stores: { nodes: [
                      { shopDomain: 'shopdomain.myshopify.com', 'transferDisabled': true },
                      { shopDomain: 'shop.myshopify.com', 'convertableToPartnerTest': true },
                      { shopDomain: 'other.myshopify.com' },
                    ] },
                  },
                ],
              },
            },
          }
        )

        CLI::UI::Prompt.expects(:ask)
          .with(
            'Select a Development Store',
            options: %w(shopdomain.myshopify.com shop.myshopify.com)
          )
          .returns('selected')
        form = ask(org_id: 123, shop: nil)
        assert_equal(form.shop_domain, 'selected')
      end

      private

      def ask(title: 'Test App', org_id: 42, shop: 'shop.myshopify.com', type: 'custom')
        Create.ask(
          @context,
          [],
          title: title,
          type: type,
          organization_id: org_id,
          shop_domain: shop,
        )
      end
    end
  end
end

