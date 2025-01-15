require "spec"
require "../src/dotenv"

private def with_tempfile(content : String)
  tempfile = File.tempfile(".env-test")
  begin
    File.write(tempfile.path, content)
    yield Path.new(tempfile.path)
  ensure
    tempfile.delete
  end
end

describe Dotenv do
  describe "#from_file" do
    it "loads an empty file" do
      with_tempfile("") do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.parse.should be_empty
      end
    end

    it "loads basic key-value pairs" do
      content = <<-EOF
      KEY1=value1
      KEY2=value2
      EOF

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.get("KEY1").should eq("value1")
        dotenv.get("KEY2").should eq("value2")
      end
    end

    it "preserves comments" do
      content = <<-EOF
      # This is a comment
      KEY1=value1
      # Another comment
      KEY2=value2
      EOF

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.dotenv_content.lines[0].should be_a(Dotenv::CommentLine)
        dotenv.dotenv_content.lines[2].should be_a(Dotenv::CommentLine)
      end
    end

    it "preserves blank lines" do
      content = <<-EOF
      KEY1=value1

      KEY2=value2
      EOF

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.dotenv_content.lines[1].should be_a(Dotenv::BlankLine)
      end
    end

    it "handles inline comments" do
      content = "KEY=value # inline comment"

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        line = dotenv.dotenv_content.lines[0].as(Dotenv::KeyValueLine)
        line.key.should eq("KEY")
        line.value.should eq("value")
        line.inline_comment.should eq(" # inline comment")
      end
    end
    it "handles inline comments with lots of space" do
      content = "KEY=value                  # inline comment"

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        line = dotenv.dotenv_content.lines[0].as(Dotenv::KeyValueLine)
        line.key.should eq("KEY")
        line.value.should eq("value")
        line.inline_comment.should eq("                  # inline comment")
      end
    end
  end

  describe "#set" do
    it "adds new key-value pairs" do
      with_tempfile("") do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.set("NEW_KEY", "new_value")
        dotenv.get("NEW_KEY").should eq("new_value")
      end
    end

    it "updates existing key-value pairs" do
      content = "EXISTING=old_value"

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.set("EXISTING", "new_value")
        dotenv.get("EXISTING").should eq("new_value")
      end
    end

    it "handles default values with + prefix" do
      content = "EXISTING=old_value"

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.set("EXISTING", "+default_value")
        dotenv.get("EXISTING").should eq("old_value") # Should keep old value

        dotenv.set("NEW_KEY", "+default_value")
        dotenv.get("NEW_KEY").should eq("default_value") # Should use default
      end
    end
  end

  describe "#parse" do
    it "returns all key-value pairs when no keys specified" do
      content = <<-EOF
      KEY1=value1
      KEY2=value2
      EOF

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        parsed = dotenv.parse
        parsed.should eq({"KEY1" => "value1", "KEY2" => "value2"})
      end
    end

    it "returns only specified keys" do
      content = <<-EOF
      KEY1=value1
      KEY2=value2
      KEY3=value3
      EOF

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        parsed = dotenv.parse(["KEY1", "KEY3"])
        parsed.should eq({"KEY1" => "value1", "KEY3" => "value3"})
      end
    end
  end

  describe "#export" do
    it "exports variables to ENV" do
      content = "EXPORT_TEST=test_value"

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.export
        ENV["EXPORT_TEST"]?.should eq("test_value")
      end
    end
  end

  describe "#generate" do
    it "generates value if key doesn't exist" do
      with_tempfile("") do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.generate("TIMESTAMP") { "test_time" }
        dotenv.get("TIMESTAMP").should eq("test_time")
      end
    end

    it "doesn't generate value if key exists" do
      content = "TIMESTAMP=existing_time"

      with_tempfile(content) do |path|
        dotenv = Dotenv.from_file(path)
        dotenv.generate("TIMESTAMP") { "new_time" }
        dotenv.get("TIMESTAMP").should eq("existing_time")
      end
    end
  end

  describe "roundtrip" do
    it "preserves file formatting exactly" do
      content = <<-EOF
      # Header comment

      # Another comment
         # Indented comment
      EMPTY=
      SPACES=   spaced   value   # With trailing comment
      QUOTES="quoted value"
      ESCAPED=escaped\\"quote
      NEWLINES=multi\\nline
      KEY=value # inline comment
      DUPE=first
      DUPE=second # second one wins
      =invalid_no_key
      invalid_no_equals
         INDENTED=value
      EOF

      with_tempfile(content) do |path|
        # Load the file
        dotenv = Dotenv.from_file(path)

        # Verify specific aspects
        dotenv.dotenv_content.lines[0].should be_a(Dotenv::CommentLine)
        dotenv.dotenv_content.lines[1].should be_a(Dotenv::BlankLine)

        empty = dotenv.dotenv_content.lines[4].as(Dotenv::KeyValueLine)
        empty.key.should eq("EMPTY")
        empty.value.should eq("")

        spaces = dotenv.dotenv_content.lines[5].as(Dotenv::KeyValueLine)
        spaces.key.should eq("SPACES")
        spaces.value.should eq("   spaced   value")
        spaces.inline_comment.should eq("   # With trailing comment")

        quotes = dotenv.dotenv_content.lines[6].as(Dotenv::KeyValueLine)
        quotes.key.should eq("QUOTES")
        quotes.value.should eq("quoted value")
        quotes.quote.should eq('"')

        escaped = dotenv.dotenv_content.lines[7].as(Dotenv::KeyValueLine)
        escaped.key.should eq("ESCAPED")
        escaped.value.should eq("escaped\\\"quote")

        newlines = dotenv.dotenv_content.lines[8].as(Dotenv::KeyValueLine)
        newlines.key.should eq("NEWLINES")
        newlines.value.should eq("multi\\nline")

        inline = dotenv.dotenv_content.lines[9].as(Dotenv::KeyValueLine)
        inline.key.should eq("KEY")
        inline.value.should eq("value")
        inline.inline_comment.should eq(" # inline comment")

        # Verify duplicate handling
        dotenv.get("DUPE").should eq("second")

        # Save and reload
        dotenv.save_file
        reloaded = Dotenv.from_file(path)

        # Verify file contents are identical
        reloaded.dotenv_content.to_s.should eq(content)
      end
    end
  end

  describe ".using" do
    it "automatically saves changes when using Path" do
      with_tempfile("KEY=value") do |path|
        initial_content = File.read(path)

        Dotenv.using(path) do |dotenv|
          dotenv.set("KEY", "new_value")
        end

        File.read(path).should_not eq(initial_content)
        File.read(path).should contain("KEY=new_value")
      end
    end

    it "doesn't save if no changes when using Path" do
      with_tempfile("KEY=value") do |path|
        initial_content = File.read(path)

        Dotenv.using(path) do |dotenv|
          # Just read, no changes
          dotenv.get("KEY")
        end

        File.read(path).should eq(initial_content)
      end
    end

    it "works with string content" do
      content = "KEY=value"
      result = Dotenv.using(content) do |dotenv|
        dotenv.get("KEY").should eq("value")
        dotenv.set("NEW_KEY", "new_value")
        "return value"
      end
      result.should eq("return value")
    end

    it "doesn't try to save when using string content" do
      content = "KEY=value"
      Dotenv.using(content) do |dotenv|
        dotenv.set("KEY", "new_value")
        # No file should be created/modified
      end
    end
  end
end
