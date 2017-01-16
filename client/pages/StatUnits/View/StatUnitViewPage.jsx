import React from 'react'
import View from './View'

class StatUnitViewPage extends React.Component {
  componentDidMount() {
    const { id, type,
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

  render() {
    const {
      unit, localize, legalUnitOptions,
      enterpriseUnitOptions, enterpriseGroupOptions,
    } = this.props
    return (
      <View
        {...{
          unit,
          localize,
          legalUnitOptions,
          enterpriseUnitOptions,
          enterpriseGroupOptions,
        }}
      />
    )
  }
}

StatUnitViewPage.propTypes = {}

export default StatUnitViewPage
