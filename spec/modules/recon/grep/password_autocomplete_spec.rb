require 'spec_helper'

describe name_from_filename do
    include_examples 'module'

    def self.targets
        %w(Generic)
    end

    def self.elements
        [ Element::FORM ]
    end

    def issue_count
        2
    end

    easy_test{ issues.map { |i| i.var }.sort.should == %w(insecure insecure_2).sort }
end
