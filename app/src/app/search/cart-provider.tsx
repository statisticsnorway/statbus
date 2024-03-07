import {createContext, ReactNode, useCallback, useContext, useMemo, useState} from "react";
import {Tables} from "@/lib/database.types";

interface CartContextData {
  readonly selected: Tables<"statistical_unit">[]
  readonly clearSelected: () => void
  readonly toggle: (unit: Tables<"statistical_unit">) => void
}

const CartContext = createContext<CartContextData | null>(null)

interface CartProviderProps {
  readonly children: ReactNode;
}

export const CartProvider = ({children}: CartProviderProps) => {

  const [selected, setSelected] = useState<Tables<"statistical_unit">[]>([])

  const toggle = useCallback((unit: Tables<"statistical_unit">) => {
    setSelected(prev => {
      const existing = prev.find(s => s.unit_id === unit.unit_id && s.unit_type === unit.unit_type);
      return existing ? prev.filter(s => s !== existing) : [...prev, unit]
    })
  }, [setSelected])


  const ctx: CartContextData = useMemo(() => ({
    selected,
    toggle,
    clearSelected: () => setSelected([])
  }), [toggle, selected])

  return (
    <CartContext.Provider value={ctx}>
      {children}
    </CartContext.Provider>
  )
}

export const useCartContext = () => {
  const context = useContext(CartContext)
  if (!context) {
    throw new Error('useCartContext must be used within a CartProvider')
  }
  return context
}
