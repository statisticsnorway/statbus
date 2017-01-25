namespace nscreg.Server.Models.Dynamic.Property
{
    public class FloatPropertyMetadata : PropertyMetadataBase
    {
        public FloatPropertyMetadata(string name, bool isRequired, decimal? value) : base(name, isRequired)
        {
            Value = value;
        }

        public decimal? Value { get; set; }
        public override PropertyType Selector => PropertyType.Float;

    }
}