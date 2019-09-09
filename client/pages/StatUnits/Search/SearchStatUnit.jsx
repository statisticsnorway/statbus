import React from 'react'
import { arrayOf, func, number, oneOfType, shape, string, bool } from 'prop-types'
import { Confirm, Header, Loader, Table } from 'semantic-ui-react'
import { isEmpty } from 'ramda'

import { statUnitTypes } from 'helpers/enums'
import { getCorrectQuery, getSearchFormErrors } from 'helpers/validation'
import Paginate from 'components/Paginate'
import SearchForm from '../SearchForm'
import ListItem from './ListItem'
import styles from './styles.pcss'
import TableHeader from './TableHeader'

class Search extends React.Component {
  static propTypes = {
    fetchData: func.isRequired,
    clear: func.isRequired,
    setSearchCondition: func.isRequired,
    updateFilter: func.isRequired,
    setQuery: func.isRequired,
    deleteStatUnit: func.isRequired,
    formData: shape({}).isRequired,
    statUnits: arrayOf(shape({
      regId: number.isRequired,
      name: string.isRequired,
    })),
    query: shape({
      wildcard: string,
      includeLiquidated: string,
    }),
    totalCount: oneOfType([number, string]),
    localize: func.isRequired,
    locale: string.isRequired,
    isLoading: bool.isRequired,
    lookups: shape({}).isRequired,
  }

  static defaultProps = {
    query: shape({
      wildcard: '',
      includeLiquidated: false,
    }),
    statUnits: [],
    totalCount: 0,
  }

  state = {
    showConfirm: false,
    selectedUnit: undefined,
  }

  handleChangeForm = (name, value) => {
    this.props.updateFilter({ [name]: value })
  }

  handleSubmitForm = (e) => {
    e.preventDefault()
    const { fetchData, setQuery, formData, query } = this.props
    if (!isEmpty(formData)) {
      const qdata = getCorrectQuery({ ...query, ...formData })
      qdata.page = 1
      setQuery(qdata)
    }
  }

  handleResetForm = () => {
    this.props.clear()
    this.props.setQuery({})
  }

  handleConfirm = () => {
    const unit = this.state.selectedUnit
    this.setState({ selectedUnit: undefined, showConfirm: false })
    const { query, formData } = this.props
    const queryParams = { ...query, ...formData }
    const unitIndex = this.props.statUnits.indexOf(unit)
    this.props.deleteStatUnit(unit.type, unit.regId, queryParams, unitIndex)
  }

  handleCancel = () => {
    this.setState({ showConfirm: false })
  }

  displayConfirm = (statUnit) => {
    this.setState({ selectedUnit: statUnit, showConfirm: true })
  }

  renderConfirm() {
    return (
      <Confirm
        open={this.state.showConfirm}
        header={`${this.props.localize('AreYouSure')}?`}
        content={`${this.props.localize('DeleteStatUnitMessage')} "${
          this.state.selectedUnit.name
        }"?`}
        onConfirm={this.handleConfirm}
        onCancel={this.handleCancel}
        confirmButton={this.props.localize('Ok')}
        cancelButton={this.props.localize('ButtonCancel')}
      />
    )
  }

  render() {
    const {
      statUnits,
      formData,
      localize,
      totalCount,
      isLoading,
      lookups,
      setSearchCondition,
      locale,
      updateFilter,
    } = this.props

    const statUnitType = statUnitTypes.get(parseInt(formData.type, 10))
    const showLegalFormColumn = statUnitType === undefined || statUnitType === 'LegalUnit'
    const searchFormErrors = getSearchFormErrors(formData, localize)

    return (
      <div className={styles.root}>
        <h2>{localize('SearchStatisticalUnits')}</h2>
        {this.state.showConfirm && this.renderConfirm()}
        <br />
        <SearchForm
          formData={formData}
          onChange={this.handleChangeForm}
          onSubmit={this.handleSubmitForm}
          onReset={this.handleResetForm}
          setSearchCondition={setSearchCondition}
          locale={locale}
          errors={searchFormErrors}
          localize={localize}
          disabled={isLoading}
        />

        <Paginate totalCount={Number(totalCount)} updateFilter={updateFilter}>
          {isLoading && (
            <div className={styles['loader-wrapper']}>
              <Loader active size="massive" />
            </div>
          )}
          {!isLoading &&
            (statUnits.length > 0 ? (
              <Table selectable fixed>
                <TableHeader localize={localize} showLegalFormColumn={showLegalFormColumn} />
                {statUnits.map(item => (
                  <ListItem
                    key={`${item.regId}_${item.type}_${item.name}`}
                    statUnit={item}
                    deleteStatUnit={this.displayConfirm}
                    localize={localize}
                    lookups={lookups}
                    showLegalFormColumn={showLegalFormColumn}
                  />
                ))}
              </Table>
            ) : (
              <Header as="h2" content={localize('ListIsEmpty')} textAlign="center" disabled />
            ))}
        </Paginate>
      </div>
    )
  }
}

export default Search
