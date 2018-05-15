namespace nscreg.Data.Entities
{
    public class SampleFrame
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public string Predicate { get; set; }
        public string Fields { get; set; }
        public string UserId { get; set; }
        public User User { get; set; }
    }
}
