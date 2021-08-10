java_import org.apache.pdfbox.pdmodel.PDDocument
java_import org.apache.pdfbox.pdmodel.encryption.StandardDecryptionMaterial

class Java::TechnologyTabula::Table
  // 让spec_index可以get和set
  attr_accessor :spec_index
  def to_csv
    sb = java.lang.StringBuilder.new
    Java::TechnologyTabulaWriters.CSVWriter.new.write(sb, self)
    sb.toString
  end

  def to_tsv
    sb = java.lang.StringBuilder.new
    Java::TechnologyTabulaWriters.TSVWriter.new.write(sb, self)
    sb.toString
  end

  def to_json(*a)
    sb = java.lang.StringBuilder.new
    Java::TechnologyTabulaWriters.JSONWriter.new.write(sb, self)
    sb.toString
  end
end


// 把文件路径和coords传入，输出已处理好的table
module Tabula

  def Tabula.(pdf_path, specs, options={})
    options = {
      :password => '',
      :detect_ruling_lines => true,
      :vertical_rulings => [],
      :extraction_method => "guess",
    }.merge(options)

    // 遍历hash数组，新增spec_index这个key，且值为i；结果如下：
    // [{"page"=>1, "extraction_method"=>"spreadsheet", "selection_id"=>"L1628578798607", "x1"=>61.00024999999998, "x2"=>532.7502499999999, "y1"=>147.99987499999997, "y2"=>792.937375, "width"=>471.75, "height"=>644.9375, "spec_index"=>0}, 
    specs.each_with_index{
      |spec, i| spec["spec_index"] = i 
    }

    // |s|为数组的一个元素，按照s['page']进行分组，返回一个hash；结果如下：
    // {1=>[{"page"=>1, "extraction_method"=>"spreadsheet", "selection_id"=>"L1628578798607", "x1"=>61.00024999999998, "x2"=>532.7502499999999, "y1"=>147.99987499999997, "y2"=>792.937375, "width"=>471.75, "height"=>644.9375, "spec_index"=>0}],
    specs = specs.group_by { |s| s['page'] }

    // 获取页数组并排序,结果如下：
    // [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    pages = specs.keys.sort

    extractor = Extraction::ObjectExtractor.new(pdf_path,
                                                options[:password])

    sea = Java::TechnologyTabulaExtractors.SpreadsheetExtractionAlgorithm.new
    bea = Java::TechnologyTabulaExtractors.BasicExtractionAlgorithm.new

    Enumerator.new do |y|

      // 遍历 pages，extract每一个page，并对page执行block的代码。
      extractor.extract(pages.map { |p| p.to_java(:int) }).each do |page|

        // 获取specs中第page.getPageNumber页，并对这个spec执行block的代码。
        specs[page.getPageNumber].each do |spec|

          if ["spreadsheet", "original", "basic", "stream", "lattice"].include?(spec['extraction_method'])
            use_spreadsheet_extraction_method = (spec['extraction_method'] == "spreadsheet" || spec['extraction_method'] == "lattice"  )
          else # guess
            use_spreadsheet_extraction_method = sea.isTabular(page)
          end

          // area是Page类型
          area = page.getArea(spec['y1'], spec['x1'], spec['y2'], spec['x2'])

          table_extractor = use_spreadsheet_extraction_method ? sea : bea

          // extract返回List<Table>类型，对每一个table执行block代码。
          table_extractor.extract(area).each { |table| table.spec_index = spec["spec_index"]; y.yield table }

        end

      end;
      extractor.close!
    end

  end





  module Extraction

    def Extraction.openPDF(pdf_filename, password='')
      raise Errno::ENOENT unless File.exists?(pdf_filename)
      PDDocument.load(java.io.File.new(pdf_filename))
    end

    class ObjectExtractor < Java::TechnologyTabula.ObjectExtractor

      alias_method :close!, :close

      # TODO: the +pages+ constructor argument does not make sense
      # now that we have +extract_page+ and +extract_pages+
      def initialize(pdf_filename, pages=[1], password='', options={})
        raise Errno::ENOENT unless File.exists?(pdf_filename)
        @pdf_filename = pdf_filename
        @document = Extraction.openPDF(pdf_filename, password)

        super(@document)
      end

      def page_count
        @document.get_number_of_pages
      end

    end

    class PagesInfoExtractor < ObjectExtractor

      def pages
        Enumerator.new do |y|
          self.extract.each do |page|
            y.yield({
                      :width => page.getWidth,
                      :height => page.getHeight,
                      :number => page.getPageNumber,
                      :rotation => page.getRotation.to_i,
                      :hasText => page.hasText
                    })
            end
        end
      end
    end
  end
end
