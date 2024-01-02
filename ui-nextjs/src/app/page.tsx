import {createClient} from "@/app/auth/_lib/supabase.server.client";
import {revalidatePath} from "next/cache";

async function setCategoryStandard(formData: FormData) {
    "use server";
    const client = createClient()
    const id = formData.get('activity_category_standard_id')
    await client.from('settings').insert({activity_category_standard_id: id})
    revalidatePath('/')
}

export default async function Home() {
    const client = createClient()

    const {data: settings} = await client.from('settings')
        .select('id, activity_category_standard(id,name)')

    const {data: standards} = await client.from('activity_category_standard')
        .select('id, name')

    return (
        <main className="flex flex-col items-center p-24">
            {
                settings?.length ? (
                    <>
                        <h2 className="mb-2 font-bold">Current settings</h2>
                        <ul className="mb-8">
                            {settings?.map(({id, activity_category_standard}) => (
                                <li key={id}>{activity_category_standard.name}</li>
                            ))}
                        </ul>
                    </>
                ) : (
                    <form action={setCategoryStandard}>
                        <h2 className="mb-4 font-bold">Please select category standard</h2>
                        <ul className="mb-8">
                            {standards?.map(({id, name}) => (
                                <li key={id}>
                                    <label className="flex items-center mb-2">
                                        <input
                                            required
                                            type="radio"
                                            value={id}
                                            className="mr-2"
                                            name="activity_category_standard_id"
                                        />
                                        {name}
                                    </label>
                                </li>
                            ))}
                        </ul>
                        <button type="submit" className="bg-blue-300 py-2 px-4 rounded">Next</button>
                    </form>
                )
            }
        </main>
    )
}
