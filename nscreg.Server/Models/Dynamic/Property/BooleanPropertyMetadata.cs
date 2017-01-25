namespace nscreg.Server.Models.Dynamic.Property
{
    public class BooleanPropertyMetadata : PropertyMetadataBase
    {
        public BooleanPropertyMetadata(string name, bool isRequired, bool? value) : base(name, isRequired)
        {
            Value = value;
        }

        public bool? Value { get; set; }
        public override PropertyType Selector => PropertyType.Boolean;
    }
}