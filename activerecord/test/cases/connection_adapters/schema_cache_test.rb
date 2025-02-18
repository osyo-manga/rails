# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class SchemaCacheTest < ActiveRecord::TestCase
      def setup
        @connection       = ARUnit2Model.connection
        @cache            = new_bound_reflection
        @database_version = @connection.get_database_version
      end

      def new_bound_reflection(connection = @connection)
        BoundSchemaReflection.new(SchemaReflection.new(nil), connection)
      end

      def load_bound_reflection(filename, connection = @connection)
        BoundSchemaReflection.new(SchemaReflection.new(filename), connection).tap do |cache|
          cache.load!
        end
      end

      def test_yaml_dump_and_load
        # Create an empty cache.
        cache = new_bound_reflection

        tempfile = Tempfile.new(["schema_cache-", ".yml"])
        # Dump it. It should get populated before dumping.
        cache.dump_to(tempfile.path)

        # Load the cache.
        cache = load_bound_reflection(tempfile.path)

        assert_no_queries do
          assert_equal 3, cache.columns("courses").size
          assert_equal 3, cache.columns_hash("courses").size
          assert cache.data_source_exists?("courses")
          assert_equal "id", cache.primary_keys("courses")
          assert_equal 1, cache.indexes("courses").size
          assert_equal @database_version.to_s, cache.database_version.to_s
        end
      ensure
        tempfile.unlink
      end

      def test_cache_path_can_be_in_directory
        cache = new_bound_reflection
        tmp_dir = Dir.mktmpdir
        filename = File.join(tmp_dir, "schema.json")

        assert_not File.exist?(filename)
        assert cache.dump_to(filename)
        assert File.exist?(filename)
      ensure
        FileUtils.rm_r(tmp_dir)
      end

      def test_yaml_dump_and_load_with_gzip
        # Create an empty cache.
        cache = new_bound_reflection

        tempfile = Tempfile.new(["schema_cache-", ".yml.gz"])
        # Dump it. It should get populated before dumping.
        cache.dump_to(tempfile.path)

        # Unzip and load manually.
        cache = Zlib::GzipReader.open(tempfile.path) do |gz|
          YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(gz.read) : YAML.load(gz.read)
        end

        assert_no_queries do
          assert_equal 3, cache.columns(@connection, "courses").size
          assert_equal 3, cache.columns_hash(@connection, "courses").size
          assert cache.data_source_exists?(@connection, "courses")
          assert_equal "id", cache.primary_keys(@connection, "courses")
          assert_equal 1, cache.indexes(@connection, "courses").size
          assert_equal @database_version.to_s, cache.database_version(@connection).to_s
        end

        # Load the cache the usual way.
        cache = load_bound_reflection(tempfile.path)

        assert_no_queries do
          assert_equal 3, cache.columns("courses").size
          assert_equal 3, cache.columns_hash("courses").size
          assert cache.data_source_exists?("courses")
          assert_equal "id", cache.primary_keys("courses")
          assert_equal 1, cache.indexes("courses").size
          assert_equal @database_version.to_s, cache.database_version.to_s
        end
      ensure
        tempfile.unlink
      end

      def test_yaml_loads_5_1_dump
        cache = load_bound_reflection(schema_dump_path)

        assert_no_queries do
          assert_equal 11, cache.columns("posts").size
          assert_equal 11, cache.columns_hash("posts").size
          assert cache.data_source_exists?("posts")
          assert_equal "id", cache.primary_keys("posts")
        end
      end

      def test_yaml_loads_5_1_dump_without_indexes_still_queries_for_indexes
        cache = load_bound_reflection(schema_dump_path)

        assert_queries :any, ignore_none: true do
          assert_equal 1, cache.indexes("courses").size
        end
      end

      def test_yaml_loads_5_1_dump_without_database_version_still_queries_for_database_version
        cache = load_bound_reflection(schema_dump_path)

        # We can't verify queries get executed because the database version gets
        # cached in both MySQL and PostgreSQL outside of the schema cache.

        assert_not_nil reflection = @cache.instance_variable_get(:@schema_reflection)
        assert_nil reflection.instance_variable_get(:@cache)

        assert_equal @database_version.to_s, cache.database_version.to_s
      end

      def test_primary_key_for_existent_table
        assert_equal "id", @cache.primary_keys("courses")
      end

      def test_primary_key_for_non_existent_table
        assert_nil @cache.primary_keys("omgponies")
      end

      def test_columns_for_existent_table
        assert_equal 3, @cache.columns("courses").size
      end

      def test_columns_for_non_existent_table
        assert_raises ActiveRecord::StatementInvalid do
          @cache.columns("omgponies")
        end
      end

      def test_columns_hash_for_existent_table
        assert_equal 3, @cache.columns_hash("courses").size
      end

      def test_columns_hash_for_non_existent_table
        assert_raises ActiveRecord::StatementInvalid do
          @cache.columns_hash("omgponies")
        end
      end

      def test_indexes_for_existent_table
        assert_equal 1, @cache.indexes("courses").size
      end

      def test_indexes_for_non_existent_table
        assert_equal [], @cache.indexes("omgponies")
      end

      def test_caches_database_version
        @cache.database_version # cache database_version

        assert_no_queries do
          assert_equal @database_version.to_s, @cache.database_version.to_s

          if current_adapter?(:Mysql2Adapter, :TrilogyAdapter)
            assert_not_nil @cache.database_version.full_version_string
          end
        end
      end

      def test_clearing
        @cache.columns("courses")
        @cache.columns_hash("courses")
        @cache.data_source_exists?("courses")
        @cache.primary_keys("courses")
        @cache.indexes("courses")

        @cache.clear!

        assert_equal 0, @cache.size
        reflection = @cache.instance_variable_get(:@schema_reflection)
        schema_cache = reflection.instance_variable_get(:@cache)
        assert_nil schema_cache.instance_variable_get(:@database_version)
      end

      def test_marshal_dump_and_load
        # Create an empty cache.
        cache = new_bound_reflection

        # Populate it.
        cache.add("courses")

        # We're going to manually dump, so we also need to force
        # database_version to be stored.
        cache.database_version

        # Create a new cache by marshal dumping / loading.
        cache = Marshal.load(Marshal.dump(cache.instance_variable_get(:@schema_reflection).instance_variable_get(:@cache)))

        assert_no_queries do
          assert_equal 3, cache.columns(@connection, "courses").size
          assert_equal 3, cache.columns_hash(@connection, "courses").size
          assert cache.data_source_exists?(@connection, "courses")
          assert_equal "id", cache.primary_keys(@connection, "courses")
          assert_equal 1, cache.indexes(@connection, "courses").size
          assert_equal @database_version.to_s, cache.database_version(@connection).to_s
        end
      end

      def test_marshal_dump_and_load_via_disk
        # Create an empty cache.
        cache = new_bound_reflection

        tempfile = Tempfile.new(["schema_cache-", ".dump"])
        # Dump it. It should get populated before dumping.
        cache.dump_to(tempfile.path)

        # Load a new cache.
        cache = load_bound_reflection(tempfile.path)

        assert_no_queries do
          assert_equal 3, cache.columns("courses").size
          assert_equal 3, cache.columns_hash("courses").size
          assert cache.data_source_exists?("courses")
          assert_equal "id", cache.primary_keys("courses")
          assert_equal 1, cache.indexes("courses").size
          assert_equal @database_version.to_s, cache.database_version.to_s
        end
      ensure
        tempfile.unlink
      end

      def test_marshal_dump_and_load_with_ignored_tables
        old_ignore = ActiveRecord.schema_cache_ignored_tables
        ActiveRecord.schema_cache_ignored_tables = ["professors"]
        # Create an empty cache.
        cache = new_bound_reflection

        tempfile = Tempfile.new(["schema_cache-", ".dump"])
        # Dump it. It should get populated before dumping.
        cache.dump_to(tempfile.path)

        # Load a new cache.
        cache = load_bound_reflection(tempfile.path)

        # Assert a table in the cache
        assert cache.data_source_exists?("courses"), "expected posts to be in the cached data_sources"
        assert_equal 3, cache.columns("courses").size
        assert_equal 3, cache.columns_hash("courses").size
        assert cache.data_source_exists?("courses")
        assert_equal "id", cache.primary_keys("courses")
        assert_equal 1, cache.indexes("courses").size

        # Assert ignored table. Behavior should match non-existent table.
        assert_nil cache.data_source_exists?("professors"), "expected comments to not be in the cached data_sources"
        assert_raises ActiveRecord::StatementInvalid do
          cache.columns("professors")
        end
        assert_raises ActiveRecord::StatementInvalid do
          cache.columns_hash("professors").size
        end
        assert_nil cache.primary_keys("professors")
        assert_equal [], cache.indexes("professors")
      ensure
        tempfile.unlink
        ActiveRecord.schema_cache_ignored_tables = old_ignore
      end

      def test_marshal_dump_and_load_with_gzip
        # Create an empty cache.
        cache = new_bound_reflection

        tempfile = Tempfile.new(["schema_cache-", ".dump.gz"])
        # Dump it. It should get populated before dumping.
        cache.dump_to(tempfile.path)

        # Load a new cache manually.
        cache = Zlib::GzipReader.open(tempfile.path) { |gz| Marshal.load(gz.read) }

        assert_no_queries do
          assert_equal 3, cache.columns(@connection, "courses").size
          assert_equal 3, cache.columns_hash(@connection, "courses").size
          assert cache.data_source_exists?(@connection, "courses")
          assert_equal "id", cache.primary_keys(@connection, "courses")
          assert_equal 1, cache.indexes(@connection, "courses").size
          assert_equal @database_version.to_s, cache.database_version(@connection).to_s
        end

        # Load a new cache.
        cache = load_bound_reflection(tempfile.path)

        assert_no_queries do
          assert_equal 3, cache.columns("courses").size
          assert_equal 3, cache.columns_hash("courses").size
          assert cache.data_source_exists?("courses")
          assert_equal "id", cache.primary_keys("courses")
          assert_equal 1, cache.indexes("courses").size
          assert_equal @database_version.to_s, cache.database_version.to_s
        end
      ensure
        tempfile.unlink
      end

      def test_data_source_exist
        assert @cache.data_source_exists?("courses")
        assert_not @cache.data_source_exists?("foo")
      end

      def test_clear_data_source_cache
        @cache.clear_data_source_cache!("courses")
      end

      test "#columns_hash? is populated by #columns_hash" do
        assert_not @cache.columns_hash?("courses")

        @cache.columns_hash("courses")

        assert @cache.columns_hash?("courses")
      end

      test "#columns_hash? is not populated by #data_source_exists?" do
        assert_not @cache.columns_hash?("courses")

        @cache.data_source_exists?("courses")

        assert_not @cache.columns_hash?("courses")
      end

      unless in_memory_db?
        def test_when_lazily_load_schema_cache_is_set_cache_is_lazily_populated_when_est_connection
          tempfile = Tempfile.new(["schema_cache-", ".yml"])
          original_config = ActiveRecord::Base.configurations.configs_for(env_name: "arunit2", name: "primary")
          new_config = original_config.configuration_hash.merge(schema_cache_path: tempfile.path)

          ActiveRecord::Base.establish_connection(new_config)

          # cache starts empty
          assert_equal 0, ActiveRecord::Base.connection.pool.schema_reflection.instance_variable_get(:@cache).size

          # now we access the cache, causing it to load
          assert ActiveRecord::Base.connection.schema_cache.version

          assert File.exist?(tempfile)
          assert ActiveRecord::Base.connection.pool.schema_reflection.instance_variable_get(:@cache)

          # assert cache is still empty on new connection (precondition for the
          # following to show it is loading because of the config change)
          ActiveRecord::Base.establish_connection(new_config)

          assert File.exist?(tempfile)
          assert_equal 0, ActiveRecord::Base.connection.pool.schema_reflection.instance_variable_get(:@cache).size

          # cache is loaded upon connection when lazily loading is on
          old_config = ActiveRecord.lazily_load_schema_cache
          ActiveRecord.lazily_load_schema_cache = true
          ActiveRecord::Base.establish_connection(new_config)

          assert File.exist?(tempfile)
          assert ActiveRecord::Base.connection.pool.schema_reflection.instance_variable_get(:@cache)
        ensure
          ActiveRecord.lazily_load_schema_cache = old_config
          ActiveRecord::Base.establish_connection(:arunit)
        end
      end

      test "#init_with skips deduplication if told to" do
        coder = {
          "columns" => [].freeze,
          "deduplicated" => true,
        }

        schema_cache = SchemaCache.allocate
        schema_cache.init_with(coder)
        assert_same coder["columns"], schema_cache.instance_variable_get(:@columns)
      end

      private
        def schema_dump_path
          "#{ASSETS_ROOT}/schema_dump_5_1.yml"
        end
    end
  end
end
