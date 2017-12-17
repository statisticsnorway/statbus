namespace nscreg.Utilities
{
    public static class Pagination
    {
        public static int CalculateSkip(int pageSize, int pageNum, int totalCount)
        {
            var initialSkip = pageSize * (pageNum - 1);
            return pageSize >= totalCount
                ? 0
                : initialSkip > totalCount
                    ? initialSkip % totalCount
                    : initialSkip;
        }
    }
}
