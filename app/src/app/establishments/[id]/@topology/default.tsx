import TopologySlot from "@/app/_statistical-unit-details/topology-slot";

export default async function StatisticalUnitHierarchySlot({params: {id}}: { readonly params: { id: string } }) {
  return <TopologySlot unitId={parseInt(id, 10)} unitType="establishment"/>
}
