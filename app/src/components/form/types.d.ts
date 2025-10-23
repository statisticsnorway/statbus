type UpdateResponse =
  | {
      status: "success";
      message: string;
    }
  | {
      status: "error";
      message: string;
      errors?: Array<{
        path: string;
        message: string;
      }>;
    }
  | null;

 type SchemaType =
   | "general-info"
   | "demographic-info"
   | "sector"
   | "legal-form";
