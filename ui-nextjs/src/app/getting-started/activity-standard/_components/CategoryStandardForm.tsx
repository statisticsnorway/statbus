"use client";
import {zodResolver} from "@hookform/resolvers/zod"
import * as z from "zod"
import {RadioGroup, RadioGroupItem} from "@/components/ui/radio-group"
import {Button} from "@/components/ui/button";
import {Form, FormControl, FormField, FormItem, FormLabel, FormMessage,} from "@/components/ui/form"
import {useForm} from "react-hook-form";
import {setCategoryStandard} from "@/app/getting-started/activity-standard/actions";

interface CategoryStandardFormProps {
    standards: { id: number, name: string }[] | null
    settings: { id: number, activity_category_standard: { id: number, name: string } | null }[] | null
}

const FormSchema = z.object({
    activity_category_standard_id: z.number({
        required_error: "You need to select an activity category standard",
    }),
})

export default function CategoryStandardForm({standards, settings}: CategoryStandardFormProps) {

    const form = useForm<z.infer<typeof FormSchema>>({
        resolver: zodResolver(FormSchema),
    })

    async function onSubmit({activity_category_standard_id}: z.infer<typeof FormSchema>) {
        const formData = new FormData()
        formData.append('activity_category_standard_id', activity_category_standard_id.toString())
        await setCategoryStandard(formData)
    }

    return (
        <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
                <FormField control={form.control} name="activity_category_standard_id" render={({field}) => (
                    <FormItem className="space-y-6">
                        <FormLabel className="text-lg">Select activity category standard</FormLabel>
                        <FormControl>
                            <RadioGroup
                                onValueChange={field.onChange}
                                defaultValue={settings?.[0]?.activity_category_standard?.id?.toString()}
                                className="flex flex-col space-y-1"
                            >
                                {
                                    standards?.map(({id, name}) => (
                                        <FormItem className="flex items-center space-x-3 space-y-0" key={id}>
                                            <FormControl>
                                                <RadioGroupItem value={id.toString()} id={id.toString()}/>
                                            </FormControl>
                                            <FormLabel className="text-md font-normal">
                                                {name}
                                            </FormLabel>
                                        </FormItem>
                                    ))
                                }
                            </RadioGroup>
                        </FormControl>
                        <FormMessage/>
                    </FormItem>
                )}/>
                <Button type="submit">Next</Button>
            </form>
        </Form>
    )
}
