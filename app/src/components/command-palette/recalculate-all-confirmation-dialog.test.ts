/**
 * Command palette "Recalculate all": what the operator is told for each
 * outcome of public.recalculate_all(). The database decides who may call it
 * (admin_user only, test/sql/394_recalculate_all.sql).
 */
jest.mock("@/context/RestClientStore", () => ({ getBrowserRestClient: jest.fn() }));
jest.mock("@/hooks/use-toast", () => ({ toast: jest.fn() }));

import { startRecalculateAll } from "./recalculate-all-confirmation-dialog";

function clientReturning(result: { data: number | null; error: { message: string } | null }) {
  const rpc = jest.fn().mockResolvedValue(result);
  return { rpc };
}

describe("startRecalculateAll", () => {
  it("calls recalculate_all once and reports that it started", async () => {
    const client = clientReturning({ data: 49262, error: null });
    await expect(startRecalculateAll(client)).resolves.toEqual({
      title: "Recalculation started",
      description:
        "Every statistical unit and report is being recalculated. Progress is shown while it runs.",
    });
    expect(client.rpc).toHaveBeenCalledTimes(1);
    expect(client.rpc).toHaveBeenCalledWith("recalculate_all");
  });

  it("says there is nothing to recalculate when no units exist", async () => {
    await expect(startRecalculateAll(clientReturning({ data: null, error: null }))).resolves.toEqual({
      title: "Nothing to recalculate",
      description: "There are no statistical units yet.",
    });
  });

  it("shows the database's refusal to a non-admin", async () => {
    const refused = clientReturning({
      data: null,
      error: { message: "permission denied for function recalculate_all" },
    });
    await expect(startRecalculateAll(refused)).resolves.toEqual({
      title: "Recalculation not started",
      description: "permission denied for function recalculate_all",
    });
  });

  it("reports a failed request", async () => {
    const client = { rpc: jest.fn().mockRejectedValue(new Error("Failed to fetch")) };
    await expect(startRecalculateAll(client)).resolves.toEqual({
      title: "Recalculation not started",
      description: "Failed to fetch",
    });
  });
});
