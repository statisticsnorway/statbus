"use client";
import { zodResolver } from "@hookform/resolvers/zod";
import * as z from "zod";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Button } from "@/components/ui/button";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { useForm } from "react-hook-form";
import { useGettingStartedManager as useGettingStarted } from '@/atoms/hooks';
import { Tables } from "@/lib/database.types";
import { setCategoryStandard } from "@/app/getting-started/getting-started-server-actions";
import { useRouter } from "next/navigation";

interface CategoryStandardFormProps {
  readonly standards: Tables<"activity_category_standard">[] | null;
  readonly settings: Tables<"settings">[] | null;
}

const FormSchema = z.object({
  activity_category_standard_id: z.coerce.number({
    required_error: "You need to select an activity category standard",
    invalid_type_error: "You need to select an activity category standard",
  }),
});

export default function CategoryStandardForm({
  standards,
  settings,
}: CategoryStandardFormProps) {
  const form = useForm<z.infer<typeof FormSchema>>({
    resolver: zodResolver(FormSchema),
    defaultValues: {
      activity_category_standard_id:
        settings?.[0]?.activity_category_standard_id,
    },
  });
  const router = useRouter();

  const { refreshAllData } = useGettingStarted();

  async function onSubmit({
    activity_category_standard_id,
  }: z.infer<typeof FormSchema>) {
    const formData = new FormData();
    formData.append(
      "activity_category_standard_id",
      activity_category_standard_id.toString(10)
    );
    const result = await setCategoryStandard(formData);
    await refreshAllData();
    if (result.success) {
      router.push("/getting-started/upload-custom-activity-standard-codes");
    }
  }

  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit(onSubmit)}
        className="space-y-6 bg-ssb-light p-6"
      >
        <FormField
          control={form.control}
          name="activity_category_standard_id"
          render={({ field }) => (
            <FormItem>
              <fieldset className="space-y-3">
                <legend>Select activity category standard</legend>
                <FormControl>
                  <RadioGroup
                    ref={field.ref}
                    name={field.name}
                    onValueChange={field.onChange}
                    defaultValue={field.value?.toString()}
                    className="flex flex-col space-y-1"
                  >
                    {standards?.map(({ id, name }) => (
                      <FormItem
                        className="flex items-center space-x-3 space-y-0"
                        key={id}
                      >
                        <FormControl>
                          <RadioGroupItem value={id.toString(10)} />
                        </FormControl>
                        <FormLabel className="text-md font-normal">
                          {name}
                        </FormLabel>
                      </FormItem>
                    ))}
                  </RadioGroup>
                </FormControl>
              </fieldset>
              <FormMessage />
            </FormItem>
          )}
        />
        <div className="space-x-3">
          <Button type="submit">Confirm</Button>
        </div>
      </form>
    </Form>
  );
}
