# ------------------------------------------------------------------------------
# This file is part of the Open Source License Compendium (OSLiC) and is
# distributed under the same terms a the LaTeX sources of OSLiC.
# ------------------------------------------------------------------------------

require "psych"
require "fileutils"
require_relative "oslic"

module YAMLBackend

  class Generator
    def initialize(xml_file, aux_file, output_directory)
      @data = Oslic::OscadData.new(xml_file, aux_file)
      @output_directory = output_directory
      FileUtils.makedirs(@output_directory)
    end
    
    def generate
      render_license_names
      render_licenses
      render_lsucs
      render_osuc
    end

    # --------------------------------------------------------------------------
    # license_names.yml
    # --------------------------------------------------------------------------

    def render_license_names
      #write_yml "license_names.yml"
    end

    # --------------------------------------------------------------------------
    # licenses.yml
    # --------------------------------------------------------------------------

    def render_licenses
      doc = new_doc
      lics = new_mapping (doc)
      @data.licenses.each do |license|
        new_scalar(license.name, lics)
        uc_map = new_mapping(lics)
        license.use_cases.each do |use_case|
          use_case.osucs.each do |osuc|
            new_quoted_scalar(osuc[5..-1], uc_map)
            new_scalar(use_case.id, uc_map)
          end
        end
      end
      write_yml "licenses.yml", doc
    end

    # --------------------------------------------------------------------------
    # lsuc.yml
    # --------------------------------------------------------------------------

    def render_lsucs
      doc = new_doc
      lsucs = new_mapping (doc)
      @data.licenses.each do |license|
        license.use_cases.each do |use_case|
          new_quoted_scalar(use_case.id, lsucs)
          render_lsuc(new_mapping(lsucs), use_case, license)
        end
      end
      write_yml "lsuc.yml", doc
    end

    def render_lsuc mapping, use_case, license
      new_scalar("license", mapping)
      render_lsuc_license(new_mapping(mapping), use_case, license)
      new_scalar("oslic", mapping)
      render_lsuc_crossref(new_mapping(mapping), use_case, license)
      new_scalar("usecase", mapping)
      render_lsuc_usecase(new_mapping(mapping), use_case, license)
    end

    def render_lsuc_license mapping, use_case, license
      new_scalar("name", mapping)
      new_quoted_scalar(license.name, mapping)

      new_scalar("specification", mapping)
      new_quoted_scalar(license.title, mapping)

      new_scalar("abbreviation", mapping)
      new_quoted_scalar(license.abbrev, mapping)

      new_scalar("release", mapping)
      new_quoted_scalar("#{license.version}", mapping) # empty string if version is nil
    end

    def render_lsuc_crossref mapping, use_case, license
      raise "No protection chapter for #{license.name}" if license.protection_chapter == "unknown"
      raise "No discussion section for #{license.name}" if license.discussion_chapter == "unknown"
      raise "No TO-DO list for #{use_case.id}" if use_case.chapter == "unknown"

      def patent_str license 
        # replace "unknown" with an empty string
        return "" if license.patent_chapter == "unknown"
        return license.patent_chapter
      end
      def todo_str use_case
        # strip last dotted section from use_case reference
        use_case.chapter[/^(.*)\.\d+$/, 1]
      end

      new_scalar("protection", mapping)
      new_quoted_scalar(license.protection_chapter, mapping)

      new_scalar("patent", mapping)
      new_quoted_scalar(patent_str(license), mapping)

      new_scalar("todo", mapping)
      new_quoted_scalar(todo_str(use_case), mapping) 

      new_scalar("lsuc", mapping)
      new_quoted_scalar(use_case.chapter, mapping)

      new_scalar("explain", mapping)
      new_quoted_scalar(license.discussion_chapter, mapping)
    end

    def render_lsuc_usecase mapping, use_case, license
      new_scalar("name", mapping)
      new_quoted_scalar(use_case.id, mapping)
      
      new_scalar("desc", mapping)
      new_folded_scalar(use_case.description.to_s, mapping)

      new_scalar("notasks", mapping)
      new_quoted_scalar("#{use_case.no_task_message}", mapping) 

      new_scalar("requires", mapping)
      render_lsuc_requires(new_mapping(mapping), use_case, license)

      new_scalar("forbids", mapping)
      render_lsuc_forbids(new_mapping(mapping), use_case, license)
    end

    def render_lsuc_requires mapping, use_case, license
      new_scalar("prefix", mapping)
      new_quoted_scalar("the following tasks in order to fulfill the license conditions", mapping)

      new_scalar("man", mapping)
      tasks = new_sequence(mapping)
      use_case.required.each do |task|
        new_folded_scalar(task.to_s, tasks)
      end

      new_scalar("vol", mapping)
      tasks = new_sequence(mapping)
      use_case.recommended.each do |task|
        new_folded_scalar(task.to_s, tasks)
      end
    end

    def render_lsuc_forbids mapping, use_case, license
      new_scalar("prefix", mapping)
      new_quoted_scalar("", mapping)

      new_scalar("array", mapping)
      tasks = new_sequence(mapping)
      use_case.prohibited.each do |task|
        new_folded_scalar(task.to_s, tasks)
      end
    end

    # --------------------------------------------------------------------------
    # osuc.yml
    # --------------------------------------------------------------------------

    def render_osuc
      doc = new_doc
      osucs = new_mapping (doc)
      @data.osucs.each do |name, description| 
        raise "Missing OSUC-name" if name == nil
        raise "No description for #{name}" if description == nil
        new_quoted_scalar(name, osucs)
        map = new_mapping(osucs)
        new_scalar("number", map)
        new_quoted_scalar(name, map)
        new_scalar("name", map)
        new_scalar("OSUC-#{name}", map)
        new_scalar("desc", map)
        new_folded_scalar(description, map)
      end
      write_yml "osuc.yml", doc
    end

    # --------------------------------------------------------------------------
    # utilities
    # --------------------------------------------------------------------------

    def write_yml filename, doc
      full_path = File.join(@output_directory, filename)
      puts "Writing #{full_path}"
      stream = Psych::Nodes::Stream.new
      stream.children << doc
      File.open(full_path, "w") { |file| file.puts (stream.to_yaml) }
    end

    def new_doc
      Psych::Nodes::Document.new
    end

    def new_mapping parent=nil
      result = Psych::Nodes::Mapping.new
      parent.children << result unless parent == nil
      return result
    end

    def new_sequence parent=nil
      result = Psych::Nodes::Sequence.new
      parent.children << result unless parent == nil
      return result
    end

    def new_scalar value, parent=nil
      result = Psych::Nodes::Scalar.new(value)
      parent.children << result unless parent == nil
      return result
    end

    def new_quoted_scalar value, parent=nil
      result = new_scalar(value, parent)
      result.quoted = true
      result.style = Psych::Nodes::Scalar::DOUBLE_QUOTED
      return result
    end

    def new_folded_scalar value, parent=nil
      result = new_scalar(value, parent)
      result.style = Psych::Nodes::Scalar::FOLDED
      return result
    end

    private :render_license_names, :render_licenses, :render_lsucs, :render_osuc
    private :render_lsuc, :render_lsuc_license, :render_lsuc_crossref, :render_lsuc_usecase
    private :write_yml, :new_mapping, :new_scalar, :new_quoted_scalar, :new_folded_scalar
  end

end

#app = YAMLBackend::LicenseNames.new
#app.add_license("01").proapse.unmodified.independent.for_yourself
#app.add_license("02S").proapse.unmodified.independent.to_others.sources
#app.add_license("02B").proapse.unmodified.independent.to_others.binaries
#puts app.show

DATA_FILE = Oslic::find_file("oscad.xml")
AUX_FILE = Oslic::find_file("oslic.aux")
OUTPUT_DIRECTORY = "oscad_data"

Oslic::FormattedString::renderer(Oslic::HTMLRenderer.new)
YAMLBackend::Generator.new(DATA_FILE, AUX_FILE, OUTPUT_DIRECTORY).generate

  # class LicenseNames
  #   def initialize
  #     @stream = Psych::Nodes::Stream.new
  #     @doc = Psych::Nodes::Document.new
  #     @seq = Psych::Nodes::Sequence.new

  #     @stream.children << @doc
  #     @doc.children << @seq
  #   end

  #   class License 
  #     attr_reader :mapping

  #     def initialize osuc
  #       @mapping = Psych::Nodes::Mapping.new
  #       return add "osuc", osuc
  #     end

  #     def proapse 
  #       return add "type", "proapse"
  #     end

  #     def snimoli
  #       return add "type", "snimoli"
  #     end

  #     def modified
  #       return add "state", "modified"
  #     end

  #     def unmodified
  #       return add "state", "unmodified"
  #     end

  #     def independent
  #       return add "context", "independent"
  #     end

  #     def embedded
  #       return add "context", "embedded"
  #     end

  #     def for_yourself
  #       return add "recipient", "4yourself" 
  #     end

  #     def to_others
  #       return add "recipient", "2others"
  #     end

  #     def sources
  #       return add "form", "sources"
  #     end

  #     def binaries
  #       return add "form", "binaries"
  #     end

  #   private 
  #     def add key, value
  #       @mapping.children << Psych::Nodes::Scalar.new(key)
  #       @mapping.children << Psych::Nodes::Scalar.new(value)
  #       return self
  #     end
  #   end

  #   def add_license osuc
  #     result = License.new(osuc)
  #     @seq.children << result.mapping
  #     return result
  #   end

  #   def show
  #     return @stream.to_yaml
  #   end
      
  # end


# ------------------------------------------------------------------------------
# Local Variables:
# mode: ruby
# fill-column: 78
# End:
# ------------------------------------------------------------------------------
