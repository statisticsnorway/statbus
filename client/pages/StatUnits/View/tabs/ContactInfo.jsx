import React from 'react'
import { shape, func, string, number } from 'prop-types'

import { Label, Grid, Segment, Form } from 'semantic-ui-react'
import PersonsGrid from 'components/fields/PersonsField'

const ContactInfo = ({ data, localize }) => (
  <div>
    <Grid>
      <Grid.Row centered columns={2}>
        <Grid.Column width={5}>
          <Segment size="mini">
            <Label pointing="right" size="small">{localize('TelephoneNo')} </Label>
            {data.telephoneNo}
          </Segment>
        </Grid.Column>
        {data.emailAddress &&
          <Grid.Column width={5}>
            <Segment size="mini">
              <Label pointing="right" size="small">{localize('Email')} </Label>
              {data.emailAddress}
            </Segment>
          </Grid.Column>}
      </Grid.Row>
    </Grid>
    {data.address &&
      <Segment.Group as={Form.Field}>
        <label htmlFor={name}>Visiting address</label>
        <Segment>
          <Grid>
            <Grid.Row relaxed columns={3}>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{`${localize('AddressPart')}1`} </Label>
                  {data.address.addressPart1}
                </Segment>
              </Grid.Column>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{`${localize('AddressPart')}2`}</Label>
                  {data.address.addressPart2}
                </Segment>
              </Grid.Column>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{`${localize('AddressPart')}3`}</Label>
                  {data.address.regionPart3}
                </Segment>
              </Grid.Column>
            </Grid.Row>
            <Grid.Row relaxed columns={2}>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{`${localize('AddressPart')}4`}</Label>
                  {data.address.gpsCoordinates}
                </Segment>
              </Grid.Column>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{localize('RegionCode')} </Label>
                  {data.address.region.code}
                </Segment>
              </Grid.Column>
            </Grid.Row>
          </Grid>
        </Segment>
      </Segment.Group>}
    <br />
    {data.actualAddress &&
      <Segment.Group as={Form.Field}>
        <label htmlFor={name}>Postal address</label>
        <Segment>
          <Grid>
            <Grid.Row relaxed columns={3}>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{localize('AddressPart1')} </Label>
                  {data.actualAddress.addressPart1}
                </Segment>
              </Grid.Column>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{localize('AddressPart2')} </Label>
                  {data.actualAddress.addressPart2}
                </Segment>
              </Grid.Column>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{localize('AddressPart3')} </Label>
                  {data.actualAddress.regionPart3}
                </Segment>
              </Grid.Column>
            </Grid.Row>
            <Grid.Row relaxed columns={2}>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{localize('GpsCoordinates')} </Label>
                  {data.actualAddress.gpsCoordinates}
                </Segment>
              </Grid.Column>
              <Grid.Column>
                <Segment size="mini">
                  <Label pointing="right" size="small">{localize('RegionCode')} </Label>
                  {data.actualAddress.region.code}
                </Segment>
              </Grid.Column>
            </Grid.Row>
          </Grid>
        </Segment>
      </Segment.Group>}
    <br />
    <Label pointing="below" size="small">{localize('PersonsRelatedToTheUnit')} </Label>
    <PersonsGrid
      name="persons"
      value={data.persons}
      localize={localize}
      readOnly
    />
  </div>
)

ContactInfo.propTypes = {
  data: shape({
    emailAddress: string.isRequired,
    telephoneNo: number.isRequired,
    address: shape.isRequired,
    actualAddress: shape.isRequired,
    persons: shape.isRequired,
  }).isRequired,
  localize: func.isRequired,
}

export default ContactInfo
