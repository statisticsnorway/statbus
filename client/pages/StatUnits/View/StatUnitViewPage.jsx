import React from 'react'
import R from 'ramda'

import View from './View'

class StatUnitViewPage extends React.Component {

  componentDidMount() {
    const {
      id,
      type,
      actions: {
        fetchStatUnit,
        fetchLocallUnitsLookup,
        fetchLegalUnitsLookup,
        fetchEnterpriseUnitsLookup,
        fetchEnterpriseGroupsLookup,
      },
    } = this.props
    fetchStatUnit(type, id)
      .then(() => fetchLocallUnitsLookup())
      .then(() => fetchLegalUnitsLookup())
      .then(() => fetchEnterpriseUnitsLookup())
      .then(() => fetchEnterpriseGroupsLookup())
  }

  shouldComponentUpdate(nextProps, nextState) {
    return !R.equals(this.props, nextProps) || !R.equals(this.state, nextState)
  }

  render() {
    const {
      unit, localize, legalUnitOptions,
      enterpriseUnitOptions, enterpriseGroupOptions,
      actions: { navigateBack },
    } = this.props
    return (
      <View
        {...{
          unit,
          localize,
          legalUnitOptions,
          enterpriseUnitOptions,
          enterpriseGroupOptions,
          navigateBack,
        }}
      />
    )
  }
}

export default StatUnitViewPage
