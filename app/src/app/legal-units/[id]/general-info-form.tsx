'use client';
import {Form, FormControl, FormField, FormItem, FormLabel, FormMessage} from "@/components/ui/form";
import {useForm} from "react-hook-form";
import {z} from "zod";
import {zodResolver} from "@hookform/resolvers/zod";
import {Input} from "@/components/ui/input";
import {Tables} from "@/lib/database.types";
import {Button} from "@/components/ui/button";
import {toast} from "@/components/ui/use-toast";

const schema = z.object({
  name: z.string().nullable(),
  tax_reg_ident: z.string().nullable()
})

type FormValue = z.infer<typeof schema>

export default function GeneralInfoForm({unit}: { unit: Tables<'legal_unit'> }) {

  const form = useForm<FormValue>({
    resolver: zodResolver(schema),
    defaultValues: unit
  })

  const submit = (value: FormValue) => {
    toast({
      title: "You submitted the following values:",
      description: (
        <pre className="mt-2 rounded-md bg-slate-950 p-4">
          <code className="text-white text-xs">{JSON.stringify(value, null, 2)}</code>
        </pre>
      ),
    })
  }

  return (
    <Form {...form}>
      <form className="space-y-8" onSubmit={form.handleSubmit(submit)}>
        <FormField
          control={form.control}
          name="name"
          render={({field: {value, ...rest}}) => (
            <FormItem>
              <FormLabel>Name</FormLabel>
              <FormControl>
                <Input placeholder="Unit name" {...rest} value={value ?? ""}/>
              </FormControl>
              <FormMessage/>
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="tax_reg_ident"
          render={({field: {value, ...rest}}) => (
            <FormItem>
              <FormLabel>Tax Reg Ident</FormLabel>
              <FormControl>
                <Input placeholder="Tax Reg Ident" {...rest} value={value ?? ""}/>
              </FormControl>
              <FormMessage/>
            </FormItem>
          )}
        />
        <Button type="submit">Update Legal Unit</Button>
      </form>
    </Form>
  )
}
